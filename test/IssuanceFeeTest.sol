// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest} from "./BaseTest.sol";
import {MIN_TICK} from "../src/MorphoV2.sol";

contract IssuanceFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = keccak256(abi.encode(obligation));

        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    /// @notice Tests basic issuance fee functionality:
    /// - Lender receives shares minus fee
    /// - Fee recipient receives fee shares
    /// - Borrower owes full debt
    /// - Total shares is unchanged
    function testBasicIssuanceFee() public {
        uint256 issuanceFee = 0.05e18; // 5%
        uint256 loanAmount = 100e18;

        morphoV2.setIssuanceFee(issuanceFee);

        // Setup lender with funds
        deal(address(loanToken), lender, loanAmount);

        // Create borrower offer
        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = loanAmount;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startTick = MIN_TICK;
        borrowerOffer.expiryTick = MIN_TICK;

        // Collateralize borrower
        collateralize(obligation, borrower, loanAmount);

        // Lender takes borrower's offer (new credit creation)
        take(loanAmount, 0, 0, 0, lender, borrowerOffer);

        // Calculate expected values
        uint256 expectedTotalShares = loanAmount; // shares = units at price MIN_TICK (price ~0.5)
        uint256 expectedFeeShares = expectedTotalShares.mulDivDown(issuanceFee, WAD);
        uint256 expectedLenderShares = expectedTotalShares - expectedFeeShares;

        // Assertions
        assertEq(morphoV2.sharesOf(lender, id), expectedLenderShares, "lender shares");
        assertEq(morphoV2.sharesOf(feeRecipient, id), expectedFeeShares, "fee recipient shares");
        assertEq(morphoV2.debtOf(borrower, id), morphoV2.totalUnits(id), "borrower owes full debt");
        assertEq(morphoV2.totalShares(id), expectedTotalShares, "total shares unchanged");
    }

    /// @notice Tests that issuance fee is NOT charged on lender-to-lender transfer
    function testNoFeeOnLenderToLenderTransfer() public {
        uint256 issuanceFee = 0.05e18; // 5%
        uint256 loanAmount = 100e18;

        morphoV2.setIssuanceFee(issuanceFee);

        // First, create initial position (lender + borrower)
        deal(address(loanToken), lender, loanAmount);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = loanAmount;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startTick = MIN_TICK;
        borrowerOffer.expiryTick = MIN_TICK;

        collateralize(obligation, borrower, loanAmount);
        take(loanAmount, 0, 0, 0, lender, borrowerOffer);

        // Record state after initial creation
        uint256 lenderSharesAfterCreation = morphoV2.sharesOf(lender, id);
        uint256 feeRecipientSharesAfterCreation = morphoV2.sharesOf(feeRecipient, id);

        // Now otherLender buys lender's position (lender-to-lender transfer)
        deal(address(loanToken), otherLender, loanAmount);

        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false; // lender is selling
        lenderSellOffer.maker = lender;
        lenderSellOffer.obligationShares = lenderSharesAfterCreation;
        lenderSellOffer.start = block.timestamp;
        lenderSellOffer.expiry = block.timestamp + 200;
        lenderSellOffer.startTick = MIN_TICK;
        lenderSellOffer.expiryTick = MIN_TICK;

        take(0, 0, 0, lenderSharesAfterCreation, otherLender, lenderSellOffer);

        // Fee recipient should NOT have gained any additional shares
        assertEq(
            morphoV2.sharesOf(feeRecipient, id),
            feeRecipientSharesAfterCreation,
            "fee recipient should not gain shares on lender transfer"
        );
        // otherLender should have all of lender's original shares
        assertEq(morphoV2.sharesOf(otherLender, id), lenderSharesAfterCreation, "otherLender gets full shares");
        assertEq(morphoV2.sharesOf(lender, id), 0, "original lender has no shares");
    }

    /// @notice Tests that only owner can set issuance fee
    function testSetIssuanceFeeOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setIssuanceFee(0.05e18);
    }

    /// @notice Tests that issuance fee cannot exceed WAD (100%)
    function testSetIssuanceFeeCappedAtWad(uint256 fee) public {
        vm.assume(fee > WAD);
        vm.expectRevert("Issuance fee too high");
        morphoV2.setIssuanceFee(fee);
    }
}
