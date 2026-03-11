// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, ORACLE_PRICE_SCALE, MAX_CONTINUOUS_FEE, PASSIVE_FEE_RECIPIENT} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_DEBT = MAX_TEST_AMOUNT / 4;

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 1000 days);

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100 days;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.rcfThreshold = 0;

        id = toId(obligation);
        midnight.setFeeRecipient(feeRecipient);

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = otherLender;
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.expiry = block.timestamp;
        lenderOffer.tick = MAX_TICK;

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        vm.prank(otherBorrower);
        midnight.setIsAuthorized(otherBorrower, address(this), true);
    }

    function setupBorrower(uint256 debt, uint256 feeRate, uint256 ttm) internal {
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, debt * 2);
        setupObligation(obligation, debt);
    }

    function testAccrualPreMaturity(uint256 debt, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupBorrower(debt, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);

        vm.warp(block.timestamp + elapsed);
        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);

        // Via repay
        uint256 snap = vm.snapshotState();
        midnight.repay(obligation, 0, borrower);
        assertEq(midnight.debtOf(id, borrower), debt + expectedFee, "debt after repay");
        assertEq(midnight.pendingFee(id, borrower), remaining - expectedFee, "remaining after repay");
        vm.revertToState(snap);

        // Via withdrawCollateral
        snap = vm.snapshotState();
        vm.prank(borrower);
        midnight.withdrawCollateral(obligation, 0, 0, borrower, borrower);
        assertEq(midnight.debtOf(id, borrower), debt + expectedFee, "debt after withdrawCollateral");
        vm.revertToState(snap);

        // Via take
        deal(address(loanToken), otherLender, 1);
        lenderOffer.obligation = obligation;
        lenderOffer.obligationShares = 1;
        lenderOffer.expiry = block.timestamp;
        lenderOffer.group = keccak256("accrual-take");
        collateralize(obligation, borrower, 1);
        take(1, borrower, lenderOffer);
        assertApproxEqAbs(midnight.debtOf(id, borrower), debt + expectedFee + 1, 1, "debt after take");
    }

    function testAccrualPostMaturity(uint256 debt, uint256 feeRate, uint256 ttm, uint256 extraTime) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);
        extraTime = bound(extraTime, 0, 360 days);

        setupBorrower(debt, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);
        vm.assume(remaining > 0);

        vm.warp(obligation.maturity + extraTime);

        // Via repay
        uint256 snap = vm.snapshotState();
        midnight.repay(obligation, 0, borrower);
        assertEq(midnight.debtOf(id, borrower), debt + remaining, "all remaining consumed (repay)");
        assertEq(midnight.pendingFee(id, borrower), 0, "remaining is zero (repay)");
        vm.revertToState(snap);

        // Via withdrawCollateral
        snap = vm.snapshotState();
        vm.prank(borrower);
        midnight.withdrawCollateral(obligation, 0, 0, borrower, borrower);
        assertEq(midnight.debtOf(id, borrower), debt + remaining, "all remaining consumed (withdrawCollateral)");
        assertEq(midnight.pendingFee(id, borrower), 0, "remaining is zero (withdrawCollateral)");
        vm.revertToState(snap);

        // Via take
        deal(address(loanToken), otherLender, 1);
        lenderOffer.obligation = obligation;
        lenderOffer.obligationShares = 1;
        lenderOffer.expiry = block.timestamp;
        lenderOffer.group = keccak256("postmaturity-take");
        collateralize(obligation, borrower, 1);
        take(1, borrower, lenderOffer);
        assertApproxEqAbs(midnight.debtOf(id, borrower), debt + remaining + 1, 1, "all remaining consumed (take)");
        assertEq(midnight.pendingFee(id, borrower), 0, "remaining is zero (take)");
    }

    function testMultipleAccrualsSumCorrectly(
        uint256 debt,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed1,
        uint256 elapsed2
    ) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 4, 360 days);
        elapsed1 = bound(elapsed1, 1, ttm / 2);
        elapsed2 = bound(elapsed2, 1, ttm / 2);

        setupBorrower(debt, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);
        vm.assume(remaining > 0);

        // Two separate accruals
        uint256 snap = vm.snapshotState();
        vm.warp(block.timestamp + elapsed1);
        midnight.repay(obligation, 0, borrower);
        vm.warp(block.timestamp + elapsed2);
        midnight.repay(obligation, 0, borrower);
        uint256 debtTwoAccruals = midnight.debtOf(id, borrower);
        vm.revertToState(snap);

        // Single accrual for same total elapsed
        vm.warp(block.timestamp + elapsed1 + elapsed2);
        midnight.repay(obligation, 0, borrower);
        uint256 debtOneAccrual = midnight.debtOf(id, borrower);

        assertApproxEqAbs(debtTwoAccruals, debtOneAccrual, 2, "two accruals ~ one accrual");
    }

    function testSingleBorrow(uint256 debt, uint256 feeRate, uint256 ttm) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);

        setupBorrower(debt, feeRate, ttm);

        uint256 expectedRemaining = (uint256(feeRate) * debt).mulDivDown(ttm, WAD);
        assertEq(midnight.pendingFee(id, borrower), expectedRemaining, "remaining after entry");
        assertEq(midnight.debtOf(id, borrower), debt, "debt unchanged at entry");
    }

    function testTwoBorrowsDifferentRates(
        uint256 debt1,
        uint256 debt2,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        debt1 = bound(debt1, 1e18, MAX_DEBT / 2);
        debt2 = bound(debt2, 1, MAX_DEBT / 2);
        rate1 = bound(rate1, 0, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        // First borrow at rate1
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), rate1);
        collateralize(obligation, borrower, (debt1 + debt2) * 2);
        setupObligation(obligation, debt1);
        uint256 remaining1 = midnight.pendingFee(id, borrower);

        // Change rate, second borrow at rate2
        midnight.setObligationContinuousFee(id, rate2);

        deal(address(loanToken), otherLender, debt2);
        lenderOffer.obligation = obligation;
        lenderOffer.obligationShares = debt2;
        lenderOffer.expiry = block.timestamp;
        lenderOffer.group = keccak256("second-borrow");

        take(debt2, borrower, lenderOffer);

        uint256 expectedAdded = (uint256(rate2) * debt2).mulDivDown(ttm, WAD);
        uint256 blendedRemaining = midnight.pendingFee(id, borrower);
        assertApproxEqAbs(blendedRemaining, remaining1 + expectedAdded, 1, "remaining blended");

        // Accrue on both
        vm.warp(block.timestamp + elapsed);
        midnight.repay(obligation, 0, borrower);

        uint256 expectedFee = blendedRemaining.mulDivDown(elapsed, ttm);
        assertApproxEqAbs(midnight.debtOf(id, borrower), debt1 + debt2 + expectedFee, 1, "debt after accrual");
        assertApproxEqAbs(
            midnight.pendingFee(id, borrower), blendedRemaining - expectedFee, 1, "remaining after accrual"
        );
    }

    function testBorrowAtMaturity(uint256 debt, uint256 feeRate) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);

        obligation.maturity = block.timestamp;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, debt * 2);
        setupObligation(obligation, debt);

        assertEq(midnight.pendingFee(id, borrower), 0, "remaining is 0 at maturity");
    }

    function testExitViaRepay(uint256 debt, uint256 exitAmount, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        debt = bound(debt, 1, MAX_DEBT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 0, ttm - 1);

        setupBorrower(debt, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);

        // Compute state after accrual
        uint256 remaining = midnight.pendingFee(id, borrower);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 debtAfterAccrual = debt + feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        exitAmount = bound(exitAmount, 0, debtAfterAccrual);

        deal(address(loanToken), address(this), exitAmount);
        midnight.repay(obligation, exitAmount, borrower);

        uint256 expectedRemaining =
            remainingAfterAccrual - remainingAfterAccrual.mulDivDown(exitAmount, debtAfterAccrual);
        assertEq(midnight.debtOf(id, borrower), debtAfterAccrual - exitAmount, "debt after repay");
        assertApproxEqAbs(midnight.pendingFee(id, borrower), expectedRemaining, 1, "remaining after repay");

        if (exitAmount == debtAfterAccrual) {
            assertEq(midnight.pendingFee(id, borrower), 0, "full repay zeroes remaining");
        }
    }

    function testExitViaLiquidation(uint256 debt, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        debt = bound(debt, 1e18, MAX_DEBT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupBorrower(debt, feeRate, ttm);

        // Make liquidatabl
        oracle1.setPrice(ORACLE_PRICE_SCALE / 4);
        vm.warp(block.timestamp + elapsed);

        // Compute expected state after accrual
        uint256 remaining = midnight.pendingFee(id, borrower);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 debtAfterAccrual = debt + feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        deal(address(loanToken), address(this), debtAfterAccrual);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        uint256 debtAfterLiquidation = midnight.debtOf(id, borrower);
        uint256 totalRemoved = debtAfterAccrual - debtAfterLiquidation;

        if (debtAfterAccrual > 0 && totalRemoved > 0) {
            uint256 expectedRemaining =
                remainingAfterAccrual - remainingAfterAccrual.mulDivDown(totalRemoved, debtAfterAccrual);
            assertApproxEqAbs(midnight.pendingFee(id, borrower), expectedRemaining, 1, "remaining after liquidation");
        }
    }

    function testFeeSharesMintedToRecipient(uint256 debt, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        debt = bound(debt, 1e18, MAX_DEBT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupBorrower(debt, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);
        vm.assume(remaining > 0);

        uint256 totalSharesBefore = midnight.totalShares(id);
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        vm.warp(block.timestamp + elapsed);
        midnight.repay(obligation, 0, borrower);

        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        if (feeUnits > 0) {
            uint256 expectedShares = feeUnits.mulDivDown(totalSharesBefore + 1, totalUnitsBefore + 1);
            assertEq(midnight.sharesOf(id, PASSIVE_FEE_RECIPIENT), expectedShares, "fee recipient shares");
        }
    }

    function testPerUserRateLockIn(
        uint256 debt1,
        uint256 debt2,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        debt1 = bound(debt1, 1e18, MAX_DEBT / 4);
        debt2 = bound(debt2, 1e18, MAX_DEBT / 4);
        rate1 = bound(rate1, 1, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 1, MAX_CONTINUOUS_FEE);
        vm.assume(rate1 != rate2);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        // Borrower 1 at rate1
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), rate1);
        collateralize(obligation, borrower, debt1 * 2);
        setupObligation(obligation, debt1);
        uint256 remaining1 = midnight.pendingFee(id, borrower);
        assertEq(remaining1, (uint256(rate1) * debt1).mulDivDown(ttm, WAD), "remaining1 from rate1");

        // Change rate, borrower 2 at rate2
        midnight.setObligationContinuousFee(id, rate2);
        collateralize(obligation, otherBorrower, debt2 * 2);
        setupOtherUsers(obligation, debt2);
        uint256 remaining2 = midnight.pendingFee(id, otherBorrower);
        assertEq(remaining2, (uint256(rate2) * debt2).mulDivDown(ttm, WAD), "remaining2 from rate2");

        vm.warp(block.timestamp + elapsed);

        midnight.repay(obligation, 0, borrower);
        midnight.repay(obligation, 0, otherBorrower);

        uint256 fee1 = midnight.debtOf(id, borrower) - debt1;
        uint256 fee2 = midnight.debtOf(id, otherBorrower) - debt2;

        assertEq(fee1, remaining1.mulDivDown(elapsed, ttm), "borrower1 fee from rate1");
        assertEq(fee2, remaining2.mulDivDown(elapsed, ttm), "borrower2 fee from rate2");
    }

    function testFeesCanMakePositionLiquidatable() public {
        uint256 debt = 100e18;
        uint256 ttm = 360 days;
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);

        uint256 snap = vm.snapshotState();

        // Without fee: borrow, warp, not liquidatable
        collateralize(obligation, borrower, debt);
        setupObligation(obligation, debt);
        vm.warp(block.timestamp + 180 days);
        deal(address(loanToken), address(this), debt * 2);
        vm.expectRevert("position is not liquidatable");
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        vm.revertToState(snap);

        // With fee: same setup, liquidatable
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        collateralize(obligation, borrower, debt);
        setupObligation(obligation, debt);
        vm.warp(block.timestamp + 180 days);
        deal(address(loanToken), address(this), debt * 2);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testIsHealthyAccountsForPendingFee() public {
        uint256 debt = 100e18;
        uint256 ttm = 360 days;

        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        collateralize(obligation, borrower, debt);
        setupObligation(obligation, debt);

        assertTrue(midnight.isHealthy(obligation, id, borrower), "healthy at entry");

        vm.warp(block.timestamp + 180 days);

        assertFalse(midnight.isHealthy(obligation, id, borrower), "unhealthy from pending fee");
    }

    function testSetContinuousFeeOnlyFeeSetter(address rdm) public {
        vm.assume(rdm != address(this));

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setObligationContinuousFee(id, 100);

        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setDefaultContinuousFee(address(loanToken), 100);
    }

    function testSetContinuousFeeTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_CONTINUOUS_FEE + 1, type(uint256).max);

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        vm.expectRevert("continuous fee too high");
        midnight.setObligationContinuousFee(id, fee);

        vm.expectRevert("continuous fee too high");
        midnight.setDefaultContinuousFee(address(loanToken), fee);
    }

    function testSetContinuousFeeSuccess(uint256 fee) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);

        midnight.setDefaultContinuousFee(address(loanToken), fee);
        assertEq(midnight.defaultContinuousFee(address(loanToken)), fee, "default fee updated");

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        midnight.setObligationContinuousFee(id, fee);
        assertEq(midnight.continuousFee(id), fee, "obligation fee updated");
    }

    function testFeeSharesRetrievableAfterRecipientChange(uint256 debt, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        debt = bound(debt, 1e18, MAX_DEBT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupBorrower(debt, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);
        vm.assume(remaining > 0);

        // Accrue fees
        vm.warp(block.timestamp + elapsed);
        midnight.repay(obligation, 0, borrower);
        uint256 feeShares = midnight.sharesOf(id, PASSIVE_FEE_RECIPIENT);
        vm.assume(feeShares > 0);

        // Repay all debt so withdrawable is filled
        uint256 totalDebt = midnight.debtOf(id, borrower);
        deal(address(loanToken), address(this), totalDebt);
        midnight.repay(obligation, totalDebt, borrower);

        // Change fee recipient
        address newRecipient = makeAddr("newFeeRecipient");
        midnight.setFeeRecipient(newRecipient);

        // New recipient can withdraw the fee shares
        vm.prank(newRecipient);
        (uint256 units,) = midnight.withdraw(obligation, 0, feeShares, PASSIVE_FEE_RECIPIENT, newRecipient);

        assertGt(units, 0, "new recipient got assets");
        assertEq(midnight.sharesOf(id, PASSIVE_FEE_RECIPIENT), 0, "passive shares drained");
        assertEq(loanToken.balanceOf(newRecipient), units, "assets received");
    }

    function testRateChangeDoesNotAffectExistingBorrower(
        uint256 debt,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        debt = bound(debt, 1e18, MAX_DEBT);
        rate1 = bound(rate1, 1, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 0, MAX_CONTINUOUS_FEE);
        vm.assume(rate1 != rate2);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupBorrower(debt, rate1, ttm);
        uint256 remaining = midnight.pendingFee(id, borrower);

        midnight.setObligationContinuousFee(id, rate2);
        assertEq(midnight.pendingFee(id, borrower), remaining, "remaining unchanged");

        vm.warp(block.timestamp + elapsed);
        midnight.repay(obligation, 0, borrower);

        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);
        assertEq(midnight.debtOf(id, borrower), debt + expectedFee, "fee from original rate");
        assertEq(midnight.pendingFee(id, borrower), remaining - expectedFee, "remaining after accrual");
    }
}
