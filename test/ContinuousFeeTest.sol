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
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        // Use shorter maturity so TTM < 180 days after reasonable time warps
        obligation.maturity = block.timestamp + 90 days;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 365 days;
        lenderOffer.tick = TICK_RANGE;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 365 days;
        borrowerOffer.tick = TICK_RANGE;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 100);

        midnight.setContinuousFeeRecipient(feeRecipient);
    }

    function testContinuousFeeAccrualBasic(uint256 initialShares, uint256 fee, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);
        // Bound timeElapsed to ensure we don't exceed maturity
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        // Set default continuous fee BEFORE creating the obligation
        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = midnight.totalShares(id);
        uint256 recipientSharesBefore = midnight.sharesOf(id, feeRecipient);
        uint256 lastUpdateBefore = midnight.lastUpdate(id);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = midnight.totalShares(id);
        uint256 recipientSharesAfter = midnight.sharesOf(id, feeRecipient);
        uint256 lastUpdateAfter = midnight.lastUpdate(id);

        uint256 expectedSharesMinted = (totalSharesBefore * timeElapsed).mulDivDown(fee, WAD);

        assertEq(totalSharesAfter, totalSharesBefore + expectedSharesMinted, "total shares should increase");
        assertEq(
            recipientSharesAfter, recipientSharesBefore + expectedSharesMinted, "recipient should receive fee shares"
        );
        assertEq(lastUpdateAfter, block.timestamp, "lastUpdate should be current timestamp");
        assertGt(lastUpdateAfter, lastUpdateBefore, "lastUpdate should have advanced");
    }

    function testContinuousFeeZeroFee(uint256 initialShares, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        // No default fee set, so fee is 0
        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = midnight.totalShares(id);
        uint256 recipientSharesBefore = midnight.sharesOf(id, feeRecipient);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = midnight.totalShares(id);
        uint256 recipientSharesAfter = midnight.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero fee");
        assertEq(recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero fee");
    }

    function testContinuousFeeZeroTimeElapsed(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);

        // Set default continuous fee BEFORE creating the obligation
        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = midnight.totalShares(id);
        uint256 recipientSharesBefore = midnight.sharesOf(id, feeRecipient);

        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = midnight.totalShares(id);
        uint256 recipientSharesAfter = midnight.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero elapsed time");
        assertEq(
            recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero elapsed time"
        );
    }

    function testContinuousFeeAccruesCumulatively(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_CONTINUOUS_FEE / 100, MAX_CONTINUOUS_FEE);

        // Set default continuous fee BEFORE creating the obligation
        midnight.setDefaultContinuousFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesInitial = midnight.totalShares(id);
        uint256 recipientSharesInitial = midnight.sharesOf(id, feeRecipient);

        // First accrual
        vm.warp(block.timestamp + 1 days);
        uint256 expectedShares1 = (totalSharesInitial * 1 days).mulDivDown(fee, WAD);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter1 = midnight.totalShares(id);
        uint256 recipientSharesAfter1 = midnight.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter1, totalSharesInitial + expectedShares1, "first accrual should match expected");
        assertEq(
            recipientSharesAfter1, recipientSharesInitial + expectedShares1, "recipient should receive first accrual"
        );

        // Second accrual (7 days later)
        vm.warp(block.timestamp + 7 days);
        uint256 expectedShares2 = (totalSharesAfter1 * 7 days).mulDivDown(fee, WAD);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter2 = midnight.totalShares(id);
        uint256 recipientSharesAfter2 = midnight.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter2, totalSharesAfter1 + expectedShares2, "second accrual should match expected");
        assertEq(
            recipientSharesAfter2, recipientSharesAfter1 + expectedShares2, "recipient should receive second accrual"
        );

        // Third accrual (30 days later)
        vm.warp(block.timestamp + 30 days);
        uint256 expectedShares3 = (totalSharesAfter2 * 30 days).mulDivDown(fee, WAD);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter3 = midnight.totalShares(id);
        uint256 recipientSharesAfter3 = midnight.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter3, totalSharesAfter2 + expectedShares3, "third accrual should match expected");
        assertEq(
            recipientSharesAfter3, recipientSharesAfter2 + expectedShares3, "recipient should receive third accrual"
        );
    }
}
