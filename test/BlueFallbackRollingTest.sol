// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {CollateralRoll, IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint256;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint64 internal constant INCENTIVE = 0.001e18;
    uint64 internal constant MAX_INCENTIVE = 1e18;
    uint256 internal constant DEBT = 10_000e18;

    address internal keeper = makeAddr("keeper");
    IMorpho internal blue;
    BlueFallbackRolling internal fallbackContract;
    Market internal midnightMarket;
    MarketParams internal blueMarketParams;
    uint256 internal blueCollateralIndex;
    uint64 internal start;

    function setUp() public override {
        super.setUp();
        start = uint64(vm.getBlockTimestamp());

        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(BLUE_LLTV);

        blueMarketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken1),
            oracle: address(oracle1),
            irm: address(0),
            lltv: BLUE_LLTV
        });
        blue.createMarket(blueMarketParams);

        fallbackContract = new BlueFallbackRolling(address(midnight), address(blue));

        midnightMarket.loanToken = address(loanToken);
        midnightMarket.chainId = block.chainid;
        midnightMarket.midnight = address(midnight);
        midnightMarket.maturity = vm.getBlockTimestamp() + 1 days;
        midnightMarket.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle1)
                })
            );
        midnightMarket.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle2)
                })
            );
        midnightMarket.collateralParams = sortCollateralParams(midnightMarket.collateralParams);
        blueCollateralIndex = midnightMarket.collateralParams[0].token == address(collateralToken1) ? 0 : 1;

        collateralize(midnightMarket, borrower, DEBT, blueCollateralIndex);
        setupMarket(midnightMarket, DEBT);

        deal(address(loanToken), address(this), 2 * DEBT);
        loanToken.approve(address(blue), type(uint256).max);
        blue.supply(blueMarketParams, 2 * DEBT, 0, lender, hex"");

        vm.prank(borrower);
        midnight.setIsAuthorized(address(fallbackContract), true, borrower);
        vm.prank(borrower);
        blue.setAuthorization(address(fallbackContract), true);
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, true);
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, DEBT));

        uint256 incentiveAssets = DEBT * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), 0);
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, midnightCollateral);
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(loanToken.balanceOf(keeper), incentiveAssets);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testAnyoneCanPartiallyRollBorrowerToBlue() public {
        uint256 totalCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        uint256 debtAssets = DEBT / 2;
        uint256 collateralAssets = totalCollateralAssets * debtAssets / DEBT;

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, debtAssets)
        );

        uint256 incentiveAssets = debtAssets * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT - debtAssets);
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            totalCollateralAssets - collateralAssets
        );
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, collateralAssets);
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(loanToken.balanceOf(keeper), incentiveAssets);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testCannotRollBeforeStart() public {
        uint64 futureStart = uint64(vm.getBlockTimestamp() + 1);
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), futureStart, INCENTIVE, true);

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, borrower, futureStart, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, DEBT)
        );
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, DEBT));
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, true);

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, DEBT));
    }

    function testRollRevertsForNonActivatedCollateralLeg() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, otherCollateralIndex, DEBT));
    }

    function testRollRevertsForDuplicateCollateralIndex() public {
        CollateralRoll[] memory legs = new CollateralRoll[](2);
        legs[0] = CollateralRoll({collateralIndex: blueCollateralIndex, blueMarketParams: blueMarketParams, assets: DEBT / 2});
        legs[1] = CollateralRoll({collateralIndex: blueCollateralIndex, blueMarketParams: blueMarketParams, assets: DEBT / 2});

        vm.expectRevert(IBlueFallbackRolling.DuplicateCollateralIndex.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, legs);
    }

    function testRollRevertsForEmptyLegsArray() public {
        vm.expectRevert(IBlueFallbackRolling.NoCollateralLegs.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, new CollateralRoll[](0));
    }

    function testRollRevertsForMixedValidAndInvalidLegs() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        uint256 debtBefore = midnight.debt(toId(midnightMarket), borrower);
        uint256 collateralBefore = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        CollateralRoll[] memory legs = new CollateralRoll[](2);
        legs[0] = CollateralRoll({collateralIndex: blueCollateralIndex, blueMarketParams: blueMarketParams, assets: DEBT / 2});
        legs[1] = CollateralRoll({collateralIndex: otherCollateralIndex, blueMarketParams: blueMarketParams, assets: DEBT / 2});

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, legs);

        assertEq(midnight.debt(toId(midnightMarket), borrower), debtBefore, "debt unchanged");
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            collateralBefore,
            "collateral unchanged"
        );
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, otherCollateralIndex, DEBT));
    }

    function testAnyoneCanRollMultipleCollateralsToBlue() public {
        (uint256 otherCollateralIndex, MarketParams memory blueMarketParams2) = _setUpSecondCollateralMarket();

        uint256 collateral0Before = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        uint256 collateral1Before = midnight.collateral(toId(midnightMarket), borrower, otherCollateralIndex);
        uint256 debtLeg0 = DEBT / 2;
        uint256 debtLeg1 = DEBT - debtLeg0;
        uint256 collateralAssets0 = collateral0Before.mulDivDown(debtLeg0, DEBT);
        // debtLeg1 equals the debt remaining after leg0, so leg1 fully drains collateral1.
        uint256 collateralAssets1 = collateral1Before;

        CollateralRoll[] memory legs = new CollateralRoll[](2);
        legs[0] = CollateralRoll({collateralIndex: blueCollateralIndex, blueMarketParams: blueMarketParams, assets: debtLeg0});
        legs[1] =
            CollateralRoll({collateralIndex: otherCollateralIndex, blueMarketParams: blueMarketParams2, assets: debtLeg1});

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, legs);

        uint256 incentiveAssets = DEBT * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0, "debt");
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            collateral0Before - collateralAssets0,
            "collateral0"
        );
        assertEq(midnight.collateral(toId(midnightMarket), borrower, otherCollateralIndex), 0, "collateral1");
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, collateralAssets0, "blue collateral0");
        assertEq(blue.position(blueMarketParams2.id(), borrower).collateral, collateralAssets1, "blue collateral1");
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0, "blue borrow0");
        assertGt(blue.position(blueMarketParams2.id(), borrower).borrowShares, 0, "blue borrow1");
        assertEq(loanToken.balanceOf(keeper), incentiveAssets, "incentive");
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0, "leftover");
    }

    function testAnyoneCanPartiallyRollMultipleCollateralsToBlue() public {
        (uint256 otherCollateralIndex, MarketParams memory blueMarketParams2) = _setUpSecondCollateralMarket();

        uint256 collateral0Before = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        uint256 collateral1Before = midnight.collateral(toId(midnightMarket), borrower, otherCollateralIndex);
        uint256 debtLeg0 = DEBT / 4;
        uint256 debtLeg1 = DEBT / 4;
        uint256 collateralAssets0 = collateral0Before.mulDivDown(debtLeg0, DEBT);
        uint256 collateralAssets1 = collateral1Before.mulDivDown(debtLeg1, DEBT - debtLeg0);

        CollateralRoll[] memory legs = new CollateralRoll[](2);
        legs[0] = CollateralRoll({collateralIndex: blueCollateralIndex, blueMarketParams: blueMarketParams, assets: debtLeg0});
        legs[1] =
            CollateralRoll({collateralIndex: otherCollateralIndex, blueMarketParams: blueMarketParams2, assets: debtLeg1});

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, legs);

        uint256 incentiveAssets = (debtLeg0 + debtLeg1) * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT - debtLeg0 - debtLeg1, "debt");
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            collateral0Before - collateralAssets0,
            "collateral0"
        );
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, otherCollateralIndex),
            collateral1Before - collateralAssets1,
            "collateral1"
        );
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, collateralAssets0, "blue collateral0");
        assertEq(blue.position(blueMarketParams2.id(), borrower).collateral, collateralAssets1, "blue collateral1");
        assertEq(loanToken.balanceOf(keeper), incentiveAssets, "incentive");
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0, "leftover");
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(midnightMarket, blueMarketParams, blueCollateralIndex, DEBT, DEBT * INCENTIVE / WAD, borrower)
        );
    }

    function testSetConfig() public view {
        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        uint64 incentive = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, incentive, true);
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, MAX_INCENTIVE, true);

        assertTrue(fallbackContract.isConfig(borrower, configId(start, MAX_INCENTIVE)));
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, false);

        assertFalse(fallbackContract.isConfig(borrower, configId(start, INCENTIVE)));

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(midnightMarket, borrower, start, INCENTIVE, _legs(blueMarketParams, blueCollateralIndex, DEBT));
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint64 otherStart = start + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), otherStart, MAX_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE)));
        assertTrue(fallbackContract.isConfig(borrower, configId(otherStart, MAX_INCENTIVE)));
    }

    function configId(uint64 _start, uint64 incentive) internal view returns (bytes32) {
        return keccak256(abi.encode(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _start, incentive));
    }

    function _legs(MarketParams memory params, uint256 collateralIndex, uint256 assets)
        internal
        pure
        returns (CollateralRoll[] memory legs)
    {
        legs = new CollateralRoll[](1);
        legs[0] = CollateralRoll({collateralIndex: collateralIndex, blueMarketParams: params, assets: assets});
    }

    /// @dev Activates a second Midnight collateral for the borrower and configures a second Blue market for it.
    function _setUpSecondCollateralMarket() internal returns (uint256 otherCollateralIndex, MarketParams memory params) {
        otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);

        params = MarketParams({
            loanToken: address(loanToken),
            collateralToken: midnightMarket.collateralParams[otherCollateralIndex].token,
            oracle: midnightMarket.collateralParams[otherCollateralIndex].oracle,
            irm: address(0),
            lltv: BLUE_LLTV
        });
        blue.createMarket(params);

        deal(address(loanToken), address(this), 2 * DEBT);
        blue.supply(params, 2 * DEBT, 0, lender, hex"");

        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(params.id()), start, INCENTIVE, true);
    }
}
