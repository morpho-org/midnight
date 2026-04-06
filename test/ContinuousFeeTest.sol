// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MAX_CONTINUOUS_FEE} from "../src/libraries/ConstantsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_CREDIT = MAX_TEST_AMOUNT / 4;

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    address internal feeClaimer = makeAddr("feeClaimer");

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 1000 days);

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100 days;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.rcfThreshold = 0;

        id = toId(obligation);
        midnight.setFeeClaimer(feeClaimer);

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
        emit EventsLib.UpdatePosition(id, lender, expectedFee, expectedFee, expectedFee);
        vm.expectEmit();
        emit EventsLib.Withdraw(lender, id, 0, lender, lender, 0);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after withdraw");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after withdraw");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, expectedFee, expectedFee, expectedFee);
        midnight.updatePosition(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after direct call");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after direct call");

        // Fee accumulated in continuousFeeCredit
        if (expectedFee > 0) {
            assertEq(midnight.continuousFeeCredit(id), expectedFee, "continuousFeeCredit");
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
        emit EventsLib.UpdatePosition(id, lender, remaining, remaining, remaining);
        vm.expectEmit();
        emit EventsLib.Withdraw(lender, id, 0, lender, lender, 0);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - remaining, "all remaining consumed (withdraw)");
        assertEq(midnight.pendingFee(id, lender), 0, "remaining is zero (withdraw)");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.UpdatePosition(id, lender, remaining, remaining, remaining);
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

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 takeAssets = exitAmount.mulDivDown(price, WAD);
        uint256 buyerPendingFeeIncrease = exitAmount.mulDivDown(feeRate * (ttm - elapsed), WAD);
        uint256 sellerPendingFeeDecrease =
            creditAfterAccrual > 0 ? remainingAfterAccrual.mulDivUp(exitAmount, creditAfterAccrual) : 0;

        if (exitAmount > 0) {
            vm.expectEmit();
            emit EventsLib.UpdatePosition(id, otherLender, 0, 0, 0);
        }
        vm.expectEmit();
        emit EventsLib.UpdatePosition(
            id, lender, credit - creditAfterAccrual, remaining - remainingAfterAccrual, feeUnits
        );
        vm.expectEmit();
        emit EventsLib.Take(
            lender,
            id,
            otherLender,
            lender,
            true,
            takeAssets,
            takeAssets,
            exitAmount,
            lender,
            keccak256("lender-exit"),
            exitAmount,
            buyerPendingFeeIncrease,
            sellerPendingFeeDecrease,
            exitAmount,
            exitAmount
        );
        take(exitAmount, lender, _makeBuyOffer(exitAmount, keccak256("lender-exit"))); // lender is taker = seller

        uint256 expectedRemaining = creditAfterAccrual > 0 ? remainingAfterAccrual - sellerPendingFeeDecrease : 0;
        assertEq(midnight.creditOf(id, lender), creditAfterAccrual - exitAmount, "credit after exit");
        assertApproxEqAbs(midnight.pendingFee(id, lender), expectedRemaining, 1, "remaining after exit");

        if (exitAmount == creditAfterAccrual) {
            assertEq(midnight.pendingFee(id, lender), 0, "full exit zeroes remaining");
        }

        assertEq(midnight.pendingFee(id, otherLender), buyerPendingFeeIncrease, "buyer pendingFee after exit");
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
        midnight.repay(obligation, credit, borrower, hex"");

        uint256 pendingFeeDecrease =
            creditAfterAccrual > 0 ? remainingAfterAccrual.mulDivUp(withdrawAmount, creditAfterAccrual) : 0;

        vm.expectEmit();
        emit EventsLib.UpdatePosition(
            id, lender, credit - creditAfterAccrual, remaining - remainingAfterAccrual, feeUnits
        );
        vm.expectEmit();
        emit EventsLib.Withdraw(lender, id, withdrawAmount, lender, lender, pendingFeeDecrease);
        vm.prank(lender);
        midnight.withdraw(obligation, withdrawAmount, lender, lender);

        uint256 expectedRemaining = creditAfterAccrual > 0 ? remainingAfterAccrual - pendingFeeDecrease : 0;

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

    function testClaimContinuousFee(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed, uint256 claimAmount)
        public
    {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);
        midnight.updatePosition(obligation, lender);

        uint256 feeAmount = midnight.continuousFeeCredit(id);
        vm.assume(feeAmount > 0);
        claimAmount = bound(claimAmount, 1, feeAmount);

        // Repay so withdrawable covers the claim.
        deal(address(loanToken), borrower, credit);
        vm.prank(borrower);
        midnight.repay(obligation, credit, borrower, hex"");

        address receiver = makeAddr("receiver");
        uint256 totalUnitsBefore = midnight.totalUnits(id);
        uint256 withdrawableBefore = midnight.withdrawable(id);

        vm.expectEmit();
        emit EventsLib.ClaimContinuousFee(feeClaimer, id, claimAmount, receiver);
        vm.prank(feeClaimer);
        midnight.claimContinuousFee(obligation, claimAmount, receiver);

        assertEq(loanToken.balanceOf(receiver), claimAmount, "receiver balance");
        assertEq(midnight.continuousFeeCredit(id), feeAmount - claimAmount, "continuousFeeCredit after claim");
        assertEq(midnight.totalUnits(id), totalUnitsBefore - claimAmount, "totalUnits after claim");
        assertEq(midnight.withdrawable(id), withdrawableBefore - claimAmount, "withdrawable after claim");
    }

    function testClaimContinuousFeeOnlyFeeClaimer(address caller) public {
        vm.assume(caller != feeClaimer);
        vm.prank(caller);
        vm.expectRevert("only fee claimer");
        midnight.claimContinuousFee(obligation, 0, caller);
    }

    function testClaimContinuousFeeExcessReverts(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);
        midnight.updatePosition(obligation, lender);

        uint256 feeAmount = midnight.continuousFeeCredit(id);
        vm.assume(feeAmount > 0);

        vm.prank(feeClaimer);
        vm.expectRevert();
        midnight.claimContinuousFee(obligation, feeAmount + 1, feeClaimer);
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

        (uint128 newCredit, uint128 newPendingFee,) = midnight.updatePositionView(obligation, id, lender);

        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), newCredit, "view matches credit");
        assertEq(midnight.pendingFee(id, lender), newPendingFee, "view matches pendingFee");
    }
}
