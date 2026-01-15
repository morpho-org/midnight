// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MAX_INTEREST_FEE} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract InterestFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 365 days;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = keccak256(abi.encode(obligation));

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 365 days;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 365 days;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 100);

        morphoV2.setInterestFeeRecipient(feeRecipient);
    }

    /// @dev Test that interest fees accrue correctly based on time elapsed and fee rate
    function testInterestFeeAccrualBasic(uint256 initialShares, uint256 fee, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);
        timeElapsed = bound(timeElapsed, 1 hours, 365 days);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        morphoV2.setInterestFee(id, fee);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(feeRecipient, id);
        uint256 lastUpdateBefore = morphoV2.lastUpdate(id);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(feeRecipient, id);
        uint256 lastUpdateAfter = morphoV2.lastUpdate(id);

        uint256 expectedSharesMinted = (totalSharesBefore * timeElapsed).mulDivDown(fee, WAD);

        assertEq(totalSharesAfter, totalSharesBefore + expectedSharesMinted, "total shares should increase");
        assertEq(
            recipientSharesAfter, recipientSharesBefore + expectedSharesMinted, "recipient should receive fee shares"
        );
        assertEq(lastUpdateAfter, block.timestamp, "lastUpdate should be current timestamp");
        assertGt(lastUpdateAfter, lastUpdateBefore, "lastUpdate should have advanced");
    }

    /// @dev Test that zero interest fee results in no shares minted
    function testInterestFeeZeroFee(uint256 initialShares, uint256 timeElapsed) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        timeElapsed = bound(timeElapsed, 1 hours, 365 days);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(feeRecipient, id);

        vm.warp(block.timestamp + timeElapsed);
        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(feeRecipient, id);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero fee");
        assertEq(recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero fee");
    }

    /// @dev Test that no time elapsed results in no shares minted
    function testInterestFeeZeroTimeElapsed(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        morphoV2.setInterestFee(id, fee);

        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 recipientSharesBefore = morphoV2.sharesOf(feeRecipient, id);

        take(0, 0, 0, 0, borrower, lenderOffer);

        uint256 totalSharesAfter = morphoV2.totalShares(id);
        uint256 recipientSharesAfter = morphoV2.sharesOf(feeRecipient, id);

        assertEq(totalSharesAfter, totalSharesBefore, "total shares should not change with zero elapsed time");
        assertEq(
            recipientSharesAfter, recipientSharesBefore, "recipient shares should not change with zero elapsed time"
        );
    }

    /// @dev Test multiple accruals over time accumulate correctly
    function testMultipleInterestFeeAccruals(uint256 initialShares, uint256 fee) public {
        initialShares = bound(initialShares, 1e18, MAX_TEST_AMOUNT);
        fee = bound(fee, MAX_INTEREST_FEE / 100, MAX_INTEREST_FEE);

        collateralize(obligation, borrower, initialShares);
        take(initialShares, 0, 0, 0, borrower, lenderOffer);

        morphoV2.setInterestFee(id, fee);

        uint256 totalSharesInitial = morphoV2.totalShares(id);
        uint256 recipientSharesInitial = morphoV2.sharesOf(feeRecipient, id);

        vm.warp(block.timestamp + 1 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter1 = morphoV2.totalShares(id);
        uint256 expectedShares1 = (totalSharesInitial * 1 days).mulDivDown(fee, WAD);

        vm.warp(block.timestamp + 7 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter2 = morphoV2.totalShares(id);
        uint256 expectedShares2 = (totalSharesAfter1 * 7 days).mulDivDown(fee, WAD);

        vm.warp(block.timestamp + 30 days);
        take(0, 0, 0, 0, borrower, lenderOffer);
        uint256 totalSharesAfter3 = morphoV2.totalShares(id);
        uint256 recipientSharesAfter3 = morphoV2.sharesOf(feeRecipient, id);
        uint256 expectedShares3 = (totalSharesAfter2 * 30 days).mulDivDown(fee, WAD);

        assertApproxEqAbs(
            totalSharesAfter1, totalSharesInitial + expectedShares1, 1, "first accrual should match expected"
        );
        assertApproxEqAbs(
            totalSharesAfter2, totalSharesAfter1 + expectedShares2, 1, "second accrual should match expected"
        );
        assertApproxEqAbs(
            totalSharesAfter3, totalSharesAfter2 + expectedShares3, 1, "third accrual should match expected"
        );

        assertApproxEqAbs(
            recipientSharesAfter3,
            recipientSharesInitial + expectedShares1 + expectedShares2 + expectedShares3,
            3,
            "recipient should receive all accumulated fees"
        );

        assertGt(totalSharesAfter3, totalSharesAfter2, "shares should grow");
        assertGt(totalSharesAfter2, totalSharesAfter1, "shares should grow");
        assertGt(totalSharesAfter1, totalSharesInitial, "shares should grow");
    }
}
