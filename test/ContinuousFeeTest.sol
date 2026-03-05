// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_CONTINUOUS_FEE = uint256(0.01e18) / uint256(365 days);

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        // Use shorter maturity so TTM < 180 days after reasonable time warps
        obligation.maturity = block.timestamp + 90 days;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken2),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationUnits = type(uint256).max;
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 365 days;
        lenderOffer.tick = TICK_RANGE;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 365 days;
        borrowerOffer.tick = TICK_RANGE;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 100);

        midnight.setContinuousFeeRecipient(feeRecipient);
    }

    function testContinuousFeeAccrualBasic(uint256 initialUnits, uint256 fee, uint256 timeElapsed) public {
        initialUnits = bound(initialUnits, 1e18, MAX_TEST_AMOUNT / 2);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialUnits);
        take(initialUnits, borrower, lenderOffer);

        int256 lenderBalanceBefore = midnight.balanceOf(id, lender);
        uint256 lastUpdateBefore = midnight.lastUpdate(id);

        vm.warp(block.timestamp + timeElapsed);
        // Trigger accrueFees via a zero-amount take.
        take(0, borrower, lenderOffer);

        int256 lenderBalanceAfter = midnight.balanceOf(id, lender);
        uint256 accruedFeesAfter = midnight.accruedFees(id);
        uint256 lastUpdateAfter = midnight.lastUpdate(id);

        assertLt(lenderBalanceAfter, lenderBalanceBefore, "lender balance should decrease from fee");
        assertGt(accruedFeesAfter, 0, "accruedFees should accrue");
        assertEq(lastUpdateAfter, block.timestamp, "lastUpdate should be current timestamp");
        assertGt(lastUpdateAfter, lastUpdateBefore, "lastUpdate should have advanced");
    }

    function testClaimFeesFull(uint256 initialUnits, uint256 fee, uint256 timeElapsed) public {
        initialUnits = bound(initialUnits, 1e18, MAX_TEST_AMOUNT / 2);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialUnits);
        take(initialUnits, borrower, lenderOffer);

        // Borrower repays to create withdrawable liquidity.
        vm.startPrank(borrower);
        loanToken.approve(address(midnight), type(uint256).max);
        deal(address(loanToken), borrower, initialUnits);
        midnight.repay(obligation, initialUnits, borrower);
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);

        // Trigger fee accrual.
        midnight.accrueFees(id);

        uint256 accruedFees = midnight.accruedFees(id);
        assertGt(accruedFees, 0, "fees should have accrued");

        address receiver = makeAddr("receiver");
        uint256 receiverBalanceBefore = loanToken.balanceOf(receiver);

        vm.prank(feeRecipient);
        midnight.claimFees(obligation, accruedFees, receiver);

        assertEq(midnight.accruedFees(id), 0, "accruedFees should be zero after full claim");
        assertEq(loanToken.balanceOf(receiver) - receiverBalanceBefore, accruedFees, "receiver should get claimed fees");
    }

    function testClaimFeesRevertsExceedsProtocolFees(uint256 initialUnits, uint256 fee, uint256 timeElapsed) public {
        initialUnits = bound(initialUnits, 1e18, MAX_TEST_AMOUNT / 2);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialUnits);
        take(initialUnits, borrower, lenderOffer);

        // Borrower repays to create withdrawable liquidity.
        vm.startPrank(borrower);
        loanToken.approve(address(midnight), type(uint256).max);
        deal(address(loanToken), borrower, initialUnits * 2);
        midnight.repay(obligation, initialUnits, borrower);
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);
        midnight.accrueFees(id);

        uint256 accruedFees = midnight.accruedFees(id);

        vm.prank(feeRecipient);
        vm.expectRevert();
        midnight.claimFees(obligation, accruedFees + 1, makeAddr("receiver"));
    }

    function testClaimFeesRevertsUnauthorized() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);

        collateralize(obligation, borrower, 1e18);
        take(1e18, borrower, lenderOffer);

        vm.warp(block.timestamp + 1 days);

        vm.prank(makeAddr("randomUser"));
        vm.expectRevert("unauthorized");
        midnight.claimFees(obligation, 1, makeAddr("receiver"));
    }
}
