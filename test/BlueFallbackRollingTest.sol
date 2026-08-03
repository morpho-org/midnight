// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint64 internal constant INCENTIVE = 0.001e18;
    uint64 internal constant MAX_INCENTIVE = 1e18;
    uint256 internal constant MAX_LTV = 0.8e18;
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
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, MAX_LTV, true);
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);

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
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, debtAssets);

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
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), futureStart, INCENTIVE, MAX_LTV, true);

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, futureStart, INCENTIVE, MAX_LTV, DEBT);
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, MAX_LTV, true);

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);
        uint256 blueCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.prank(borrower);
        midnight.withdrawCollateral(midnightMarket, blueCollateralIndex, blueCollateralAssets, borrower, borrower);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);
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
        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE, MAX_LTV)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        uint64 incentive = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, incentive, MAX_LTV, true);
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, MAX_INCENTIVE, MAX_LTV, true);

        assertTrue(fallbackContract.isConfig(borrower, configId(start, MAX_INCENTIVE, MAX_LTV)));
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, MAX_LTV, false);

        assertFalse(fallbackContract.isConfig(borrower, configId(start, INCENTIVE, MAX_LTV)));

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, MAX_LTV, DEBT);
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint64 otherStart = start + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), otherStart, MAX_INCENTIVE, MAX_LTV, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE, MAX_LTV)));
        assertTrue(fallbackContract.isConfig(borrower, configId(otherStart, MAX_INCENTIVE, MAX_LTV)));
    }

    function testRollRevertsWhenMaxLtvExceeded() public {
        uint256 tightMaxLtv = BLUE_LLTV / 2;
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, tightMaxLtv, true);

        vm.expectRevert(IBlueFallbackRolling.LtvExceeded.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, tightMaxLtv, DEBT);
    }

    function testRollRevertsWhenMaxLtvIsAboveLltv() public {
        uint256 invalidMaxLtv = BLUE_LLTV;
        vm.prank(borrower);
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE, invalidMaxLtv, true);

        vm.expectRevert(IBlueFallbackRolling.InvalidMaxLtv.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, start, INCENTIVE, invalidMaxLtv, DEBT);
    }

    function configId(uint64 _start, uint64 incentive, uint256 _maxLtv) internal view returns (bytes32) {
        return keccak256(abi.encode(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _start, incentive, _maxLtv));
    }
}
