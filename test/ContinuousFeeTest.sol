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
        uint256 borrowerDebtBefore = midnight.debtOf(id, borrower);
        uint256 borrowerLastUpdateBefore = midnight.userLastUpdate(id, borrower);

        vm.warp(block.timestamp + timeElapsed);
        // Trigger accrueFees and slash directly.
        midnight.accrueFees(id, lender);
        midnight.accrueFees(id, borrower);
        midnight.slash(id, lender);
        midnight.slash(id, borrower);

        int256 lenderBalanceAfter = midnight.balanceOf(id, lender);
        uint256 borrowerDebtAfter = midnight.debtOf(id, borrower);
        int256 feeRecipientBalanceAfter = midnight.balanceOf(id, feeRecipient);
        uint256 borrowerLastUpdateAfter = midnight.userLastUpdate(id, borrower);

        assertEq(lenderBalanceAfter, lenderBalanceBefore, "lender balance should not change from fee");
        assertGt(borrowerDebtAfter, borrowerDebtBefore, "borrower debt should increase from fee");
        assertGt(feeRecipientBalanceAfter, 0, "fee recipient should accrue balance");
        assertEq(borrowerLastUpdateAfter, block.timestamp, "userLastUpdate should be current timestamp");
        assertGt(borrowerLastUpdateAfter, borrowerLastUpdateBefore, "userLastUpdate should have advanced");
    }

    function testFeeRecipientWithdraw(uint256 initialUnits, uint256 fee, uint256 timeElapsed) public {
        initialUnits = bound(initialUnits, 1e18, MAX_TEST_AMOUNT / 2);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialUnits);
        take(initialUnits, borrower, lenderOffer);

        // Warp time so fees accrue on outstanding debt.
        vm.warp(block.timestamp + timeElapsed);

        // Trigger fee accrual to know the debt with fees.
        midnight.accrueFees(id, borrower);

        uint256 totalDebt = midnight.debtOf(id, borrower);
        uint256 feeRecipientBalance = uint256(midnight.balanceOf(id, feeRecipient));
        assertGt(feeRecipientBalance, 0, "fee recipient should have balance");

        // Borrower repays full debt (including accrued fees) to create withdrawable liquidity.
        vm.startPrank(borrower);
        loanToken.approve(address(midnight), type(uint256).max);
        deal(address(loanToken), borrower, totalDebt);
        midnight.repay(obligation, totalDebt, borrower);
        vm.stopPrank();

        uint256 receiverBalanceBefore = loanToken.balanceOf(feeRecipient);

        // Fee recipient withdraws their balance.
        vm.prank(feeRecipient);
        midnight.withdraw(obligation, feeRecipientBalance, feeRecipient, feeRecipient);

        assertEq(midnight.balanceOf(id, feeRecipient), 0, "fee recipient balance should be zero after withdraw");
        assertEq(
            loanToken.balanceOf(feeRecipient) - receiverBalanceBefore,
            feeRecipientBalance,
            "fee recipient should receive tokens"
        );
    }
}
