// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MAX_CONTINUOUS_FEE, PASSIVE_FEE_RECIPIENT} from "../src/libraries/ConstantsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_CREDIT = MAX_TEST_AMOUNT / 4;

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
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

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        vm.prank(otherBorrower);
        midnight.setIsAuthorized(otherBorrower, address(this), true);
    }

    /// @dev Sets up a lend + borrow position. After: lender.pendingFee = credit * feeRate * ttm / WAD,
    /// borrower.pendingFee = 0.
    function setupLender(uint256 credit, uint256 feeRate, uint256 ttm) internal {
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, credit * 2);
        setupObligation(obligation, credit);
    }

    function _makeBuyOffer(uint256 units, bytes32 group) internal view returns (Offer memory o) {
        o.obligation = obligation;
        o.buy = true;
        o.maker = otherLender;
        o.maxUnits = units;
        o.expiry = block.timestamp;
        o.tick = MAX_TICK;
        o.group = group;
    }

    function testAccrualPreMaturity(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);

        vm.warp(block.timestamp + elapsed);
        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);

        // Via withdraw(0)
        uint256 snap = vm.snapshotState();
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, credit - expectedFee, remaining - expectedFee, expectedFee);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after withdraw");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after withdraw");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, credit - expectedFee, remaining - expectedFee, expectedFee);
        midnight.updatePosition(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after direct call");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after direct call");

        // Fee credit minted to recipient
        if (expectedFee > 0) {
            assertEq(midnight.creditOf(id, PASSIVE_FEE_RECIPIENT), expectedFee, "fee recipient credit");
        }
    }

    function testAccrualPostMaturity(uint256 credit, uint256 feeRate, uint256 ttm, uint256 extraTime) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);
        extraTime = bound(extraTime, 0, 360 days);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        vm.warp(obligation.maturity + extraTime);

        // Via withdraw(0)
        uint256 snap = vm.snapshotState();
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, credit - remaining, 0, remaining);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - remaining, "all remaining consumed (withdraw)");
        assertEq(midnight.pendingFee(id, lender), 0, "remaining is zero (withdraw)");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, credit - remaining, 0, remaining);
        midnight.updatePosition(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - remaining, "all remaining consumed (direct)");
        assertEq(midnight.pendingFee(id, lender), 0, "remaining is zero (direct)");
    }

    function testMultipleAccrualsSumCorrectly(
        uint256 credit,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed1,
        uint256 elapsed2
    ) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 4, 360 days);
        elapsed1 = bound(elapsed1, 1, ttm / 2);
        elapsed2 = bound(elapsed2, 1, ttm / 2);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        // Two separate accruals
        uint256 snap = vm.snapshotState();
        vm.warp(block.timestamp + elapsed1);
        midnight.updatePosition(obligation, lender);
        vm.warp(block.timestamp + elapsed2);
        midnight.updatePosition(obligation, lender);
        uint256 creditTwoAccruals = midnight.creditOf(id, lender);
        vm.revertToState(snap);

        // Single accrual for same total elapsed
        vm.warp(block.timestamp + elapsed1 + elapsed2);
        midnight.updatePosition(obligation, lender);
        uint256 creditOneAccrual = midnight.creditOf(id, lender);

        assertApproxEqAbs(creditTwoAccruals, creditOneAccrual, 2, "two accruals ~ one accrual");
    }

    function testSingleLend(uint256 credit, uint256 feeRate, uint256 ttm) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);

        setupLender(credit, feeRate, ttm);

        uint256 expectedRemaining = (uint256(feeRate) * credit).mulDivDown(ttm, WAD);
        assertEq(midnight.pendingFee(id, lender), expectedRemaining, "lender remaining after entry");
        assertEq(midnight.pendingFee(id, borrower), 0, "borrower has no pending fee");
        assertEq(midnight.debtOf(id, borrower), credit, "debt unchanged at entry");
    }

    function _makeBorrowOffer(uint256 credit2) internal view returns (Offer memory borrowOffer) {
        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = otherBorrower;
        borrowOffer.receiverIfMakerIsSeller = otherBorrower;
        borrowOffer.maxUnits = credit2;
        borrowOffer.start = block.timestamp;
        borrowOffer.expiry = block.timestamp;
        borrowOffer.tick = MAX_TICK;
    }

    function testTwoLendersDifferentRates(
        uint256 credit1,
        uint256 credit2,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit1 = bound(credit1, 1e18, MAX_CREDIT / 2);
        credit2 = bound(credit2, 1, MAX_CREDIT / 2);
        rate1 = bound(rate1, 0, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        // First lend at rate1
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), rate1);
        collateralize(obligation, borrower, (credit1 + credit2) * 2);
        setupObligation(obligation, credit1);
        uint256 remaining1 = midnight.pendingFee(id, lender);

        // Change rate, lender adds more credit at rate2
        midnight.setObligationContinuousFee(id, rate2);
        collateralize(obligation, otherBorrower, credit2 * 2);
        deal(address(loanToken), lender, credit2);
        take(credit2, lender, _makeBorrowOffer(credit2));

        uint256 blendedRemaining = midnight.pendingFee(id, lender);
        uint256 expectedAdded = (uint256(rate2) * credit2).mulDivDown(ttm, WAD);
        assertApproxEqAbs(blendedRemaining, remaining1 + expectedAdded, 1, "remaining blended");

        // Accrue
        vm.warp(block.timestamp + elapsed);
        midnight.updatePosition(obligation, lender);

        uint256 expectedFee = blendedRemaining.mulDivDown(elapsed, ttm);
        assertApproxEqAbs(midnight.creditOf(id, lender), credit1 + credit2 - expectedFee, 1, "credit after accrual");
        assertApproxEqAbs(midnight.pendingFee(id, lender), blendedRemaining - expectedFee, 1, "remaining after accrual");
    }

    function testExitViaLenderTake(uint256 credit, uint256 exitAmount, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 0, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);

        // Compute state after accrual
        uint256 remaining = midnight.pendingFee(id, lender);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 creditAfterAccrual = credit - feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        exitAmount = bound(exitAmount, 0, creditAfterAccrual);

        // Lender exits via take (lender is seller, otherLender is buyer)
        deal(address(loanToken), otherLender, exitAmount);

        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, otherLender, 0, 0, 0);
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, creditAfterAccrual, remainingAfterAccrual, feeUnits);
        uint256 expectedRemaining = creditAfterAccrual > 0
            ? remainingAfterAccrual - remainingAfterAccrual.mulDivUp(exitAmount, creditAfterAccrual)
            : 0;
        take(exitAmount, lender, _makeBuyOffer(exitAmount, keccak256("lender-exit"))); // lender is taker = seller
        assertEq(midnight.creditOf(id, lender), creditAfterAccrual - exitAmount, "credit after exit");
        assertApproxEqAbs(midnight.pendingFee(id, lender), expectedRemaining, 1, "remaining after exit");

        if (exitAmount == creditAfterAccrual) {
            assertEq(midnight.pendingFee(id, lender), 0, "full exit zeroes remaining");
        }

        uint256 buyerExpectedPending = exitAmount.mulDivDown(feeRate * (ttm - elapsed), WAD);
        assertEq(midnight.pendingFee(id, otherLender), buyerExpectedPending, "buyer pendingFee after exit");
        assertEq(midnight.creditOf(id, otherLender), exitAmount, "buyer credit after exit");
    }

    function testWithdrawReducesPendingFee(
        uint256 credit,
        uint256 withdrawAmount,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 0, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);

        uint256 remaining = midnight.pendingFee(id, lender);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 creditAfterAccrual = credit - feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        withdrawAmount = bound(withdrawAmount, 0, creditAfterAccrual);

        deal(address(loanToken), borrower, credit);
        vm.prank(borrower);
        midnight.repay(obligation, credit, borrower);

        vm.prank(lender);
        midnight.withdraw(obligation, withdrawAmount, lender, lender);

        uint256 expectedRemaining = creditAfterAccrual > 0
            ? remainingAfterAccrual - remainingAfterAccrual.mulDivUp(withdrawAmount, creditAfterAccrual)
            : 0;

        assertEq(midnight.creditOf(id, lender), creditAfterAccrual - withdrawAmount, "credit after withdraw");
        assertApproxEqAbs(midnight.pendingFee(id, lender), expectedRemaining, 1, "remaining after withdraw");

        if (withdrawAmount == creditAfterAccrual) {
            assertEq(midnight.pendingFee(id, lender), 0, "full withdraw zeroes remaining");
            midnight.updatePosition(obligation, lender);
            assertEq(midnight.pendingFee(id, lender), 0, "full withdraw stays at zero");
        }
    }

    function testAccrualAfterSlashReducesPendingFee(
        uint256 credit,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed1,
        uint256 elapsed2
    ) public {
        credit = bound(credit, 100, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed1 = bound(elapsed1, 1, ttm - 2);
        elapsed2 = bound(elapsed2, 1, ttm - elapsed1 - 1);

        setupLender(credit, feeRate, ttm);

        // Phase 1: accrue fees on original credit before the slash.
        vm.warp(block.timestamp + elapsed1);
        midnight.updatePosition(obligation, lender);

        uint256 creditBeforeSlash = midnight.creditOf(id, lender);

        // Slash.
        createBadDebt(obligation);
        midnight.updatePosition(obligation, lender);

        uint256 creditAfterSlash = midnight.creditOf(id, lender);
        vm.assume(creditAfterSlash < creditBeforeSlash);

        uint256 pendingAfterSlash = midnight.pendingFee(id, lender);

        // Phase 2: accrue fees on slashed credit.
        vm.warp(block.timestamp + elapsed2);
        uint256 accruedFee = pendingAfterSlash.mulDivDown(elapsed2, ttm - elapsed1);

        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), creditAfterSlash - accruedFee, "credit after slash and accrual");
        assertApproxEqAbs(
            midnight.pendingFee(id, lender), pendingAfterSlash - accruedFee, 1, "remaining after slash and accrual"
        );
    }

    function testUpdatePositionViewCorrect(
        uint256 credit,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed,
        bool withBadDebt
    ) public {
        credit = bound(credit, 100, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);

        if (withBadDebt) createBadDebt(obligation);

        vm.warp(block.timestamp + elapsed);

        (uint128 expectedCredit, uint128 expectedPending,) = midnight.updatePositionView(obligation, id, lender);

        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), expectedCredit, "view matches credit");
        assertEq(midnight.pendingFee(id, lender), expectedPending, "view matches pendingFee");
    }
}
