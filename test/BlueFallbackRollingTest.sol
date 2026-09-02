// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {stdError} from "../lib/forge-std/src/Test.sol";
import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, CollateralParams, Offer} from "../src/interfaces/IMidnight.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {ISellCallback} from "../src/interfaces/ICallbacks.sol";
import {WAD, ORACLE_PRICE_SCALE, CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/interfaces/IBlueFallbackRolling.sol";
import {ERC20Lib} from "../src/periphery/libraries/ERC20Lib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint256 internal constant INCENTIVE_AT_START = 0.0002e18;
    uint256 internal constant INCENTIVE_AT_END = 0.001e18;
    uint256 internal constant MAX_INCENTIVE = 1e18;
    uint256 internal constant DEBT = 10_000e18;
    uint256 internal constant MIN_ROLLABLE_ASSETS = 2_500e18;
    uint256 internal constant MIN_REMAINING_DEBT = 0;
    uint256 internal constant MIN_FUZZED_ASSETS = 0.0001e18;

    address internal keeper = makeAddr("keeper");
    IMorpho internal blue;
    BlueFallbackRolling internal fallbackContract;
    Market internal midnightMarket;
    MarketParams internal blueMarketParams;
    uint256 internal blueCollateralIndex;
    uint256 internal start;
    uint256 internal end;

    function setUp() public override {
        super.setUp();
        start = vm.getBlockTimestamp();

        end = start + 12 hours;

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
        ERC20Lib.safeApprove(address(loanToken), address(blue), type(uint256).max);
        blue.supply(blueMarketParams, 2 * DEBT, 0, lender, hex"");

        vm.prank(borrower);
        midnight.setIsAuthorized(address(fallbackContract), true, borrower);
        vm.prank(borrower);
        blue.setAuthorization(address(fallbackContract), true);
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.warp(end);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        uint256 incentiveAssets = DEBT * INCENTIVE_AT_END / WAD;
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
        vm.warp(end);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            debtAssets
        );

        uint256 incentiveAssets = debtAssets * INCENTIVE_AT_END / WAD;
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

    function testAnyoneCanFullyRollAnUnhealthyMidnightPosition() public {
        Oracle(midnightMarket.collateralParams[blueCollateralIndex].oracle).setPrice(ORACLE_PRICE_SCALE * 95 / 100);
        assertFalse(midnight.isHealthy(midnightMarket, toId(midnightMarket), borrower));

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), 0);
    }

    function testPartialRollRevertsWhenRoundingMakesAHealthyMidnightPositionUnhealthy() public {
        uint256 debtAssets = DEBT - 1;
        uint256 extraCollateral = 1e18;
        deal(address(collateralToken1), borrower, extraCollateral);
        vm.startPrank(borrower);
        ERC20Lib.safeApprove(address(collateralToken1), address(midnight), 0);
        ERC20Lib.safeApprove(address(collateralToken1), address(midnight), extraCollateral);
        midnight.supplyCollateral(midnightMarket, blueCollateralIndex, extraCollateral, borrower);
        vm.stopPrank();

        Oracle oracle = Oracle(midnightMarket.collateralParams[blueCollateralIndex].oracle);
        oracle.setPrice(ORACLE_PRICE_SCALE - 200);
        assertTrue(midnight.isHealthy(midnightMarket, toId(midnightMarket), borrower));

        vm.expectRevert(IMidnight.UnhealthyBorrower.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            debtAssets
        );
    }

    function testRollPaysTheFlatIncentiveWhenBothBoundsAreEqual(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_START,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_START,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * INCENTIVE_AT_START / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAtEndPaysTheEndIncentive() public {
        vm.warp(end);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * INCENTIVE_AT_END / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollPaysTheAuctionedIncentive(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * expectedIncentive(elapsed) / WAD);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollPaysTheAuctionedIncentiveWhenTheAuctionEndsAfterMaturity() public {
        uint256 lateEnd = midnightMarket.maturity + 1 days;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            lateEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
        vm.warp(midnightMarket.maturity);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            lateEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        uint256 elapsed = midnightMarket.maturity - start;
        uint256 expected = INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * elapsed / (lateEnd - start);
        assertLt(expected, INCENTIVE_AT_END);
        assertEq(loanToken.balanceOf(keeper), DEBT * expected / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAtStartPaysTheStartIncentive() public {
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * INCENTIVE_AT_START / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testCannotRollBeforeStart() public {
        uint256 futureStart = vm.getBlockTimestamp() + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            futureStart,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            futureStart,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testCannotRollAfterEnd(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);
        vm.warp(end + elapsed);

        vm.expectRevert(IBlueFallbackRolling.Ended.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testRollRevertsForUnconfiguredEnd() public {
        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end + 1,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
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
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(
                midnightMarket, blueMarketParams, blueCollateralIndex, DEBT, DEBT * INCENTIVE_AT_END / WAD, borrower
            )
        );
    }

    function testRollRevertsWhileLiquidationLocked() public {
        uint256 units = 1e18;
        RollSellCallback callback = new RollSellCallback(address(fallbackContract));
        Offer memory borrowerOffer = _setupMarketOffer(midnightMarket);
        borrowerOffer.callback = address(callback);
        borrowerOffer.callbackData = abi.encode(
            blueMarketParams,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT / 2
        );
        deal(address(loanToken), lender, 2 * units);
        collateralize(midnightMarket, borrower, units, blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.LiquidationLocked.selector);
        vm.prank(lender);
        midnight.take(borrowerOffer, hex"", units, lender, address(0), address(0), hex"");
    }

    function testSetConfig() public view {
        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
    }

    function testSetConfigRevertsForTooLargeIncentiveAtEnd() public {
        uint256 incentiveAtEnd = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(
            address(this),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            incentiveAtEnd,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigRevertsForTooLargeIncentiveAtStart() public {
        uint256 incentiveAtStart = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(
            address(this),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            incentiveAtStart,
            incentiveAtStart,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigRevertsForDecreasingIncentive() public {
        vm.expectRevert(IBlueFallbackRolling.DecreasingIncentive.selector);
        fallbackContract.setConfig(
            address(this),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_END,
            INCENTIVE_AT_START,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigRevertsForEndBeforeStart() public {
        vm.expectRevert(IBlueFallbackRolling.EndNotAfterStart.selector);
        fallbackContract.setConfig(
            address(this),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            start - 1,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigRevertsForEndAtStart() public {
        vm.expectRevert(IBlueFallbackRolling.EndNotAfterStart.selector);
        fallbackContract.setConfig(
            address(this),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            start,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            MAX_INCENTIVE,
            MAX_INCENTIVE,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        assertTrue(
            fallbackContract.isConfig(
                borrower, configId(start, end, MAX_INCENTIVE, MAX_INCENTIVE, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            false
        );

        assertFalse(
            fallbackContract.isConfig(
                borrower,
                configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint256 otherStart = start + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            otherStart,
            end,
            MAX_INCENTIVE,
            MAX_INCENTIVE,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(otherStart, end, MAX_INCENTIVE, MAX_INCENTIVE, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
    }

    function testSetConfigEmitsSetConfig() public {
        vm.expectEmit(address(fallbackContract));
        emit IBlueFallbackRolling.SetConfig(
            borrower,
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            false
        );

        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            false
        );
    }

    function testSetConfigByMidnightAuthorizedCaller() public {
        vm.prank(borrower);
        midnight.setIsAuthorized(lender, true, borrower);
        uint256 otherEnd = end + 1;

        vm.expectEmit(address(fallbackContract));
        emit IBlueFallbackRolling.SetConfig(
            lender,
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            otherEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        vm.prank(lender);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            otherEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );

        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(start, otherEnd, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
    }

    function testSetConfigRevertsForUnauthorizedCaller() public {
        vm.expectRevert(IBlueFallbackRolling.Unauthorized.selector);
        vm.prank(keeper);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testSetConfigChecksAuthorizationFirst() public {
        vm.expectRevert(IBlueFallbackRolling.Unauthorized.selector);
        vm.prank(keeper);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            start,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
    }

    function testRollEmitsRoll() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.warp(end);

        vm.expectEmit(address(fallbackContract));
        emit IBlueFallbackRolling.Roll(
            keeper,
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT),
            DEBT,
            collateralAssets,
            DEBT * INCENTIVE_AT_END / WAD
        );

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testRollTransfersNoIncentiveWhenTheIncentiveIsZero(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            0,
            0,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            true
        );
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, 0, 0, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT, DEBT
        );

        assertEq(loanToken.balanceOf(keeper), 0);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    /// @dev Rolling with zero assets reverts in Blue's supply collateral.
    function testRollRevertsForZeroAssets() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            0,
            MIN_REMAINING_DEBT,
            true
        );

        vm.expectRevert(bytes("zero assets"));
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            0,
            MIN_REMAINING_DEBT,
            0
        );
    }

    function testRollRevertsForAssetsBelowMinRollableAssets() public {
        vm.expectRevert(IBlueFallbackRolling.RolledAssetsTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            MIN_ROLLABLE_ASSETS - 1
        );
    }

    function testRollAtMinRollableAssets() public {
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            MIN_ROLLABLE_ASSETS
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT - MIN_ROLLABLE_ASSETS);
    }

    function testRollRevertsForPartialRollWhenDebtIsBelowMinRollableAssets() public {
        uint256 minRollableAssets = DEBT + 1;
        uint256 assets = DEBT / 4;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.RolledAssetsTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            assets
        );
    }

    /// @dev One wei of debt above `minRollableAssets` is enough for the constraint to apply.
    function testRollRevertsWhenDebtIsJustAboveMinRollableAssets() public {
        uint256 minRollableAssets = DEBT - 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.RolledAssetsTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            minRollableAssets - 1
        );
    }

    function testRollAllowsFullRollBelowMinRollableAssets() public {
        uint256 minRollableAssets = type(uint256).max;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            DEBT
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAllowsFullRollOfRemainderBelowMinRollableAssets() public {
        uint256 remainder = MIN_ROLLABLE_ASSETS - 1;

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT - remainder
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), remainder);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            remainder
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), 0);
    }

    function testRollRevertsForPartialRollOfRemainderBelowMinRollableAssets() public {
        uint256 remainder = MIN_ROLLABLE_ASSETS - 1;

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT - remainder
        );

        vm.expectRevert(IBlueFallbackRolling.RolledAssetsTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            remainder / 2
        );
    }

    function testRollRevertsWhenRemainingDebtTooLow() public {
        uint256 minRemainingDebt = DEBT / 4;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            minRemainingDebt,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.RemainingDebtTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            minRemainingDebt,
            DEBT - minRemainingDebt + 1
        );
    }

    function testRollAllowsFullRollBelowMinRemainingDebt() public {
        uint256 minRemainingDebt = type(uint256).max;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            minRemainingDebt,
            true
        );

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            minRemainingDebt,
            DEBT
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollRevertsForUnconfiguredMinRollableAssets() public {
        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS + 1,
            MIN_REMAINING_DEBT,
            DEBT
        );
    }

    function testSetConfigDoesNotReplaceConfigWithOtherMinRollableAssets() public {
        uint256 otherMinRollableAssets = MIN_ROLLABLE_ASSETS + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            otherMinRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );

        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, MIN_ROLLABLE_ASSETS, MIN_REMAINING_DEBT)
            )
        );
        assertTrue(
            fallbackContract.isConfig(
                borrower,
                configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, otherMinRollableAssets, MIN_REMAINING_DEBT)
            )
        );
    }

    function testRollRevertsWithFuzzedMinRollableAssets(uint256 minRollableAssets, uint256 assets) public {
        minRollableAssets = bound(minRollableAssets, 1, 2 * DEBT);
        assets = bound(assets, 0, minRollableAssets < DEBT ? minRollableAssets - 1 : DEBT - 1);
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );
        uint256 totalCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.RolledAssetsTooLow.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            assets
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), totalCollateralAssets);
        assertEq(loanToken.balanceOf(keeper), 0);
    }

    function testRollSucceedsWithFuzzedMinRollableAssets(uint256 minRollableAssets, uint256 assets) public {
        minRollableAssets = bound(minRollableAssets, 0, 2 * DEBT);
        uint256 minAssets = MIN_FUZZED_ASSETS;
        if (minRollableAssets > MIN_FUZZED_ASSETS) minAssets = minRollableAssets;
        if (minAssets > DEBT) minAssets = DEBT;
        assets = bound(assets, minAssets, DEBT);
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );
        uint256 totalCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            assets
        );

        uint256 collateralAssets = totalCollateralAssets * assets / DEBT;
        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT - assets);
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            totalCollateralAssets - collateralAssets
        );
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, collateralAssets);
        assertEq(loanToken.balanceOf(keeper), assets * INCENTIVE_AT_START / WAD);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testRollAllowsFullRollOfRemainderWithFuzzedMinRollableAssets(
        uint256 minRollableAssets,
        uint256 firstAssets
    ) public {
        minRollableAssets = bound(minRollableAssets, 1, DEBT - MIN_FUZZED_ASSETS);
        firstAssets = bound(
            firstAssets,
            minRollableAssets > MIN_FUZZED_ASSETS ? minRollableAssets : MIN_FUZZED_ASSETS,
            DEBT - MIN_FUZZED_ASSETS
        );
        uint256 remainder = DEBT - firstAssets;
        vm.prank(borrower);
        fallbackContract.setConfig(
            borrower,
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            true
        );

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            firstAssets
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), remainder);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            minRollableAssets,
            MIN_REMAINING_DEBT,
            remainder
        );

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), 0);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testRollRevertsForAssetsGreaterThanDebt() public {
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            MIN_ROLLABLE_ASSETS,
            MIN_REMAINING_DEBT,
            DEBT + 1
        );
    }

    function expectedIncentive(uint256 elapsed) internal view returns (uint256) {
        uint256 duration = end - start;
        return INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * elapsed / duration;
    }

    function configId(
        uint256 _start,
        uint256 _end,
        uint256 incentiveAtStart,
        uint256 incentiveAtEnd,
        uint256 minRollableAssets,
        uint256 minRemainingDebt
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                toId(midnightMarket),
                Id.unwrap(blueMarketParams.id()),
                _start,
                _end,
                incentiveAtStart,
                incentiveAtEnd,
                minRollableAssets,
                minRemainingDebt
            )
        );
    }
}

contract RollSellCallback is ISellCallback {
    IBlueFallbackRolling internal immutable FALLBACK_CONTRACT;

    constructor(address fallbackContract) {
        FALLBACK_CONTRACT = IBlueFallbackRolling(fallbackContract);
    }

    function onSell(
        bytes32,
        Market memory market,
        uint256,
        uint256,
        uint256,
        address seller,
        address,
        bytes memory data
    ) external returns (bytes32) {
        (
            MarketParams memory blueMarketParams,
            uint64 start,
            uint64 end,
            uint64 incentiveAtStart,
            uint64 incentiveAtEnd,
            uint128 minRollableAssets,
            uint128 minRemainingDebt,
            uint256 assets
        ) = abi.decode(data, (MarketParams, uint64, uint64, uint64, uint64, uint128, uint128, uint256));
        FALLBACK_CONTRACT.roll(
            market,
            blueMarketParams,
            seller,
            start,
            end,
            incentiveAtStart,
            incentiveAtEnd,
            minRollableAssets,
            minRemainingDebt,
            assets
        );
        return CALLBACK_SUCCESS;
    }
}
