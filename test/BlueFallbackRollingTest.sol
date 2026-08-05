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
    uint64 internal constant INCENTIVE_AT_START = 0.0002e18;
    uint64 internal constant INCENTIVE_AT_MATURITY = 0.001e18;
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
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            INCENTIVE_AT_START,
            INCENTIVE_AT_MATURITY,
            true
        );
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.warp(midnightMarket.maturity);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );

        uint256 incentiveAssets = DEBT * INCENTIVE_AT_MATURITY / WAD;
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
        vm.warp(midnightMarket.maturity);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, debtAssets
        );

        uint256 incentiveAssets = debtAssets * INCENTIVE_AT_MATURITY / WAD;
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

    function testIncentiveIsTheStartIncentiveBeforeAndAtStart() public view {
        assertEq(
            fallbackContract.incentive(start + 1, midnightMarket.maturity, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY),
            INCENTIVE_AT_START
        );
        assertEq(
            fallbackContract.incentive(start, midnightMarket.maturity, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY),
            INCENTIVE_AT_START
        );
    }

    function testIncentiveGrowsLinearlyUntilMaturity(uint256 elapsed) public {
        uint256 duration = midnightMarket.maturity - start;
        elapsed = bound(elapsed, 0, duration);
        vm.warp(start + elapsed);

        assertEq(
            fallbackContract.incentive(start, midnightMarket.maturity, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY),
            expectedIncentive(elapsed)
        );
    }

    function testIncentiveIsFlatWhenBothBoundsAreEqual(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, midnightMarket.maturity - start);
        vm.warp(start + elapsed);

        assertEq(
            fallbackContract.incentive(start, midnightMarket.maturity, INCENTIVE_AT_START, INCENTIVE_AT_START),
            INCENTIVE_AT_START
        );
    }

    function testIncentiveIsCappedAfterMaturity(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 100 * 365 days);
        vm.warp(midnightMarket.maturity + elapsed);

        assertEq(
            fallbackContract.incentive(start, midnightMarket.maturity, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY),
            INCENTIVE_AT_MATURITY
        );
    }

    function testRollPaysTheAuctionedIncentive(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, midnightMarket.maturity - start);
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * expectedIncentive(elapsed) / WAD);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAtStartPaysTheStartIncentive() public {
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * INCENTIVE_AT_START / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    /// @dev Measures the gas of a full roll: supplyCollateral on Blue, borrow on Blue, repay and
    /// withdrawCollateral on Midnight, plus the incentive transfer. Rolls at maturity so the incentive is maximal.
    function testGasFullRoll() public {
        vm.warp(midnightMarket.maturity);

        // Copy the params to memory beforehand so the gasleft() window only covers the roll itself.
        Market memory _midnightMarket = midnightMarket;
        MarketParams memory _blueMarketParams = blueMarketParams;

        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        fallbackContract.roll(
            _midnightMarket, _blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: full roll", gasUsed);

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testCannotRollBeforeStart() public {
        uint64 futureStart = uint64(vm.getBlockTimestamp() + 1);
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            futureStart,
            INCENTIVE_AT_START,
            INCENTIVE_AT_MATURITY,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, futureStart, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            INCENTIVE_AT_START,
            INCENTIVE_AT_MATURITY,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);
        uint256 blueCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.prank(borrower);
        midnight.withdrawCollateral(midnightMarket, blueCollateralIndex, blueCollateralAssets, borrower, borrower);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(
                midnightMarket,
                blueMarketParams,
                blueCollateralIndex,
                DEBT,
                DEBT * INCENTIVE_AT_MATURITY / WAD,
                borrower
            )
        );
    }

    function testSetConfig() public view {
        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        uint64 incentiveAtMaturity = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, INCENTIVE_AT_START, incentiveAtMaturity, true
        );
    }

    function testSetConfigRevertsForDecreasingIncentive() public {
        vm.expectRevert(IBlueFallbackRolling.IncentiveNotIncreasing.selector);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            INCENTIVE_AT_MATURITY + 1,
            INCENTIVE_AT_MATURITY,
            true
        );
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, MAX_INCENTIVE, MAX_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, MAX_INCENTIVE, MAX_INCENTIVE)));
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            INCENTIVE_AT_START,
            INCENTIVE_AT_MATURITY,
            false
        );

        assertFalse(fallbackContract.isConfig(borrower, configId(start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY)));

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY, DEBT
        );
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint64 otherStart = start + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), otherStart, MAX_INCENTIVE, MAX_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, INCENTIVE_AT_START, INCENTIVE_AT_MATURITY)));
        assertTrue(fallbackContract.isConfig(borrower, configId(otherStart, MAX_INCENTIVE, MAX_INCENTIVE)));
    }

    /// @dev The incentive `elapsed` seconds into the auction, interpolated between the two configured bounds.
    function expectedIncentive(uint256 elapsed) internal view returns (uint256) {
        uint256 duration = midnightMarket.maturity - start;
        return INCENTIVE_AT_START + (INCENTIVE_AT_MATURITY - INCENTIVE_AT_START) * elapsed / duration;
    }

    function configId(uint64 _start, uint64 incentiveAtStart, uint64 incentiveAtMaturity)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _start, incentiveAtStart, incentiveAtMaturity
            )
        );
    }
}
