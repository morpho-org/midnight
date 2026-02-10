// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MAX_INTEREST_FEE, INTEREST_FEE_STEP} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract InterestFeeTest is BaseTest {
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

        morphoV2.setInterestFeeRecipient(feeRecipient);
    }

    function actualFee(uint256 fee) internal pure returns (uint256) {
        return uint256(uint16(fee / INTEREST_FEE_STEP)) * INTEREST_FEE_STEP;
    }

    function testInterestFeeAccrualBasic(uint256 initialShares, uint256 fee, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);
        fee = fee / INTEREST_FEE_STEP * INTEREST_FEE_STEP; // Align to INTEREST_FEE_STEP
        // Bound timeElapsed to ensure we don't exceed maturity
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        // Set default interest fee BEFORE creating the obligation
        morphoV2.setDefaultInterestFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(id, feeRecipient);
        uint256 lastUpdateBefore = morphoV2.lastUpdate(id);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(id, feeRecipient);
        uint256 lastUpdateAfter = morphoV2.lastUpdate(id);

        // Calculate expected shares using actual (truncated) fee, matching implementation formula
        uint256 _actualFee = actualFee(fee);
        uint256 expectedSharesMinted = (totalSharesBefore * timeElapsed).mulDivDown(_actualFee, WAD);

        assertEq(totalSharesAfter, totalSharesBefore + expectedSharesMinted, "total shares should increase");
        assertEq(
            recipientSharesAfter, recipientSharesBefore + expectedSharesMinted, "recipient should receive fee shares"
        );
        assertEq(lastUpdateAfter, block.timestamp, "lastUpdate should be current timestamp");
        assertGt(lastUpdateAfter, lastUpdateBefore, "lastUpdate should have advanced");
    }

    function testInterestFeeZeroFee(uint256 initialShares, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        timeElapsed = bound(timeElapsed, 1 hours, 89 days);

        // No default fee set, so fee is 0
        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(id, feeRecipient);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero fee");
        assertEq(recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero fee");
    }

    function testInterestFeeZeroTimeElapsed(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);
        fee = fee / INTEREST_FEE_STEP * INTEREST_FEE_STEP; // Align to INTEREST_FEE_STEP

        // Set default interest fee BEFORE creating the obligation
        morphoV2.setDefaultInterestFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(id, feeRecipient);

        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(id, feeRecipient);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero elapsed time");
        assertEq(
            recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero elapsed time"
        );
    }

    function testInterestFeeAccruesOnlyOnce(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);
        fee = fee / INTEREST_FEE_STEP * INTEREST_FEE_STEP; // Align to INTEREST_FEE_STEP

        // Set default interest fee BEFORE creating the obligation
        morphoV2.setDefaultInterestFee(address(loanToken), fee);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesInitial = morphoV2.totalShares(id);
        uint256 recipientSharesInitial = morphoV2.sharesOf(id, feeRecipient);

        // First accrual
        vm.warp(block.timestamp + 1 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter1 = morphoV2.totalShares(id);
        uint256 recipientSharesAfter1 = morphoV2.sharesOf(id, feeRecipient);

        // Calculate expected shares for first accrual
        uint256 _actualFee = actualFee(fee);
        uint256 expectedShares1 = (totalSharesInitial * 1 days).mulDivDown(_actualFee, WAD);

        // Second take - should NOT accrue additional interest (early return)
        vm.warp(block.timestamp + 7 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter2 = morphoV2.totalShares(id);
        uint256 recipientSharesAfter2 = morphoV2.sharesOf(id, feeRecipient);

        // Third take - should NOT accrue additional interest (early return)
        vm.warp(block.timestamp + 30 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter3 = morphoV2.totalShares(id);
        uint256 recipientSharesAfter3 = morphoV2.sharesOf(id, feeRecipient);

        // First accrual should match expected
        assertEq(totalSharesAfter1, totalSharesInitial + expectedShares1, "first accrual should match expected");
        assertEq(
            recipientSharesAfter1, recipientSharesInitial + expectedShares1, "recipient should receive first accrual"
        );

        // Subsequent takes should NOT change shares (early return due to recipient having shares)
        assertEq(totalSharesAfter2, totalSharesAfter1, "second take should not change total shares");
        assertEq(recipientSharesAfter2, recipientSharesAfter1, "second take should not change recipient shares");

        assertEq(totalSharesAfter3, totalSharesAfter1, "third take should not change total shares");
        assertEq(recipientSharesAfter3, recipientSharesAfter1, "third take should not change recipient shares");
    }
}
