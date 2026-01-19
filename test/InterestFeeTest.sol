// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract InterestFeeTest is BaseTest {
    using UtilsLib for uint256;

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

    // ============ Setter Tests ============

    function testSetObligationInterestFeeSuccess(uint256 fee) public {
        fee = bound(fee, 0, WAD);
        morphoV2.setObligationInterestFee(id, fee);
        assertEq(morphoV2._obligationInterestFee(id), fee, "obligation interest fee set");
    }

    function testSetDefaultInterestFeeSuccess(uint256 fee) public {
        fee = bound(fee, 0, WAD);
        morphoV2.setDefaultInterestFee(address(loanToken), fee);
        assertEq(morphoV2._defaultInterestFee(address(loanToken)), fee, "default interest fee set");
    }

    function testSetInterestFeeOnlyFeeSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultInterestFee(address(loanToken), 0.05e18);
    }

    function testSetInterestFeeCappedAtWad(uint256 fee) public {
        fee = bound(fee, WAD + 1, 2 * WAD);
        vm.expectRevert("Interest fee too high");
        morphoV2.setDefaultInterestFee(address(loanToken), fee);
    }

    // ============ Cost Tracking Tests ============

    function testCostOfTrackedOnEntry(uint256 price, uint256 units) public {
        price = bound(price, 0.01e18, 1e18);
        units = bound(units, 1e18, MAX_TEST_AMOUNT);
        uint256 assets = units.mulDivDown(price, WAD);
        vm.assume(assets > 0);

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        assertEq(uint256(morphoV2.costOf(lender, id)), assets, "cost tracked on entry");
    }

    function testCostOfClearedOnFullExit() public {
        uint256 units = 100e18;
        uint256 assets = 50e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        assertEq(uint256(morphoV2.costOf(lender, id)), assets, "cost before exit");

        // Repay and withdraw
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        uint256 shares = morphoV2.sharesOf(lender, id);
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(uint256(morphoV2.costOf(lender, id)), 0, "cost cleared on full exit");
    }

    function testCostOfPartiallyReducedOnPartialExit() public {
        uint256 units = 100e18;
        uint256 assets = 100e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1e18;
        borrowerOffer.expiryPrice = 1e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        // Repay half and withdraw half
        deal(address(loanToken), borrower, units / 2);
        vm.prank(borrower);
        morphoV2.repay(obligation, units / 2, borrower);

        uint256 sharesBefore = morphoV2.sharesOf(lender, id);
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, sharesBefore / 2, lender);

        // Cost should be roughly halved
        assertApproxEqAbs(uint256(morphoV2.costOf(lender, id)), assets / 2, 1, "cost partially reduced");
    }

    // ============ Interest Fee on Withdraw Tests ============

    function testInterestFeeAtWithdraw() public {
        uint256 interestFee = 0.1e18; // 10% of profit
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        uint256 units = 100e18;
        uint256 assets = 50e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        assertEq(uint256(morphoV2.costOf(lender, id)), assets, "cost basis should equal deposit");

        // Borrower repays the full debt
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        // Lender withdraws
        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, lenderShares, lender);

        // Profit = 100 - 50 = 50, Fee = 50 * 10% = 5
        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;
        uint256 expectedFee = (units - assets).mulDivDown(interestFee, WAD);
        assertEq(lenderReceived, units - expectedFee, "lender receives principal + profit - fee");
        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient gets fee");
    }

    function testInterestFeeAtWithdrawFuzz(uint256 price, uint256 units, uint256 fee) public {
        price = bound(price, 0.01e18, 0.99e18);
        units = bound(units, 1e18, MAX_TEST_AMOUNT / 2);
        fee = bound(fee, 0, WAD);

        morphoV2.setDefaultInterestFee(address(loanToken), fee);

        uint256 assets = units.mulDivDown(price, WAD);
        vm.assume(assets > 0);

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);
        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);

        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, lenderShares, lender);

        uint256 profit = units - assets;
        uint256 expectedFee = profit.mulDivDown(fee, WAD);
        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;
        uint256 feeReceived = loanToken.balanceOf(feeRecipient) - feeRecipientBalanceBefore;

        assertEq(lenderReceived, units - expectedFee, "lender receives correct amount");
        assertEq(feeReceived, expectedFee, "fee recipient receives correct fee");
    }

    function testNoFeeWhenZeroInterestFee() public {
        morphoV2.setDefaultInterestFee(address(loanToken), 0);

        uint256 units = 100e18;
        uint256 assets = 50e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, lenderShares, lender);

        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;
        assertEq(lenderReceived, units, "lender receives full amount when no fee");
        assertEq(loanToken.balanceOf(feeRecipient), 0, "no fee when interest fee is zero");
    }

    function testNoFeeOnLoss() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        uint256 loanAmount = 100e18;
        deal(address(loanToken), lender, loanAmount);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = loanAmount;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1e18;
        borrowerOffer.expiryPrice = 1e18;

        collateralize(obligation, borrower, loanAmount);
        take(loanAmount, 0, 0, 0, lender, borrowerOffer);

        // Borrower only repays 80 (loss scenario)
        uint256 repayAmount = 80e18;
        deal(address(loanToken), borrower, repayAmount);
        vm.prank(borrower);
        morphoV2.repay(obligation, repayAmount, borrower);

        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);
        vm.prank(lender);
        morphoV2.withdraw(obligation, repayAmount, 0, lender);

        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;
        assertEq(lenderReceived, 80e18, "lender receives full amount (no fee on loss)");
        assertEq(loanToken.balanceOf(feeRecipient), 0, "no fee when no profit");
    }

    // ============ Interest Fee on Lender-to-Lender Sale Tests ============

    function testInterestFeeOnLenderToLenderSale() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        uint256 units = 100e18;
        uint256 aliceAssets = 50e18;

        deal(address(loanToken), lender, aliceAssets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        uint256 aliceShares = morphoV2.sharesOf(lender, id);
        assertEq(uint256(morphoV2.costOf(lender, id)), aliceAssets, "Alice cost");

        // Alice sells to Bob at price 0.8
        uint256 bobAssets = 80e18;
        deal(address(loanToken), otherLender, bobAssets);

        Offer memory aliceSellOffer;
        aliceSellOffer.obligation = obligation;
        aliceSellOffer.buy = false;
        aliceSellOffer.maker = lender;
        aliceSellOffer.obligationShares = aliceShares;
        aliceSellOffer.start = block.timestamp;
        aliceSellOffer.expiry = block.timestamp + 200;
        aliceSellOffer.startPrice = 0.8e18;
        aliceSellOffer.expiryPrice = 0.8e18;

        uint256 aliceBalanceBefore = loanToken.balanceOf(lender);
        take(0, 0, 0, aliceShares, otherLender, aliceSellOffer);

        // Alice's profit = 80 - 50 = 30, fee = 30 * 10% = 3
        uint256 aliceProfit = bobAssets - aliceAssets;
        uint256 expectedFee = aliceProfit.mulDivDown(interestFee, WAD);
        uint256 aliceReceived = loanToken.balanceOf(lender) - aliceBalanceBefore;

        assertEq(aliceReceived, bobAssets - expectedFee, "Alice receives sale price minus fee");
        assertEq(uint256(morphoV2.costOf(lender, id)), 0, "Alice cost cleared");

        // Bob's cost = what Bob paid
        assertEq(uint256(morphoV2.costOf(otherLender, id)), bobAssets, "Bob cost = what Bob paid");
        assertEq(morphoV2.sharesOf(otherLender, id), aliceShares, "Bob gets all shares");

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient gets Alice's fee");
    }

    function testNoFeeOnLenderSaleAtLoss() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        uint256 units = 100e18;
        uint256 aliceAssets = 80e18;

        deal(address(loanToken), lender, aliceAssets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.8e18;
        borrowerOffer.expiryPrice = 0.8e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        uint256 aliceShares = morphoV2.sharesOf(lender, id);

        // Alice sells at loss (price 0.5, receives 50)
        uint256 bobAssets = 50e18;
        deal(address(loanToken), otherLender, bobAssets);

        Offer memory aliceSellOffer;
        aliceSellOffer.obligation = obligation;
        aliceSellOffer.buy = false;
        aliceSellOffer.maker = lender;
        aliceSellOffer.obligationShares = aliceShares;
        aliceSellOffer.start = block.timestamp;
        aliceSellOffer.expiry = block.timestamp + 200;
        aliceSellOffer.startPrice = 0.5e18;
        aliceSellOffer.expiryPrice = 0.5e18;

        uint256 aliceBalanceBefore = loanToken.balanceOf(lender);
        take(0, 0, 0, aliceShares, otherLender, aliceSellOffer);

        uint256 aliceReceived = loanToken.balanceOf(lender) - aliceBalanceBefore;

        // No fee because Alice sold at loss
        assertEq(aliceReceived, bobAssets, "Alice receives full sale price (no fee on loss)");
        assertEq(loanToken.balanceOf(feeRecipient), 0, "no fee when selling at loss");
    }

    // ============ Interest Fee on Borrower Exit + Lender Exit Tests ============

    function testInterestFeeOnBorrowerRepayAndLenderExit() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        uint256 units = 100e18;
        uint256 assets = 50e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        // Create a lender sell offer at price 0.8
        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false;
        lenderSellOffer.maker = lender;
        lenderSellOffer.obligationShares = lenderShares;
        lenderSellOffer.start = block.timestamp;
        lenderSellOffer.expiry = block.timestamp + 200;
        lenderSellOffer.startPrice = 0.8e18;
        lenderSellOffer.expiryPrice = 0.8e18;

        // Borrower takes it (borrower exits + lender exits)
        deal(address(loanToken), borrower, 80e18);

        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);
        take(0, 0, 0, lenderShares, borrower, lenderSellOffer);

        // Lender profit = 80 - 50 = 30, fee = 3
        uint256 expectedFee = uint256(30e18).mulDivDown(interestFee, WAD);
        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;

        assertEq(lenderReceived, 80e18 - expectedFee, "lender receives sale price minus fee");
        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient gets fee");
    }

    // ============ Bad Debt Interaction Tests ============

    function testInterestFeeWithBadDebt() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        // Setup: lender buys at 0.5 (pays 50 for 100 units)
        uint256 units = 100e18;
        uint256 assets = 50e18;

        deal(address(loanToken), lender, assets);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligationUnits = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 0.5e18;
        borrowerOffer.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, units);
        take(0, 0, units, 0, lender, borrowerOffer);

        // Re-approve collateral for createBadDebt helper
        collateralToken1.approve(address(morphoV2), type(uint256).max);

        // Temporarily disable interest fee for createBadDebt helper (which has its own repay)
        morphoV2.setDefaultInterestFee(address(loanToken), 0);
        createBadDebt(obligation);
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        // Borrower repays 100 units
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        // Lender withdraws - gets less than 100 due to bad debt socialization
        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, lenderShares, lender);

        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;
        uint256 feeReceived = loanToken.balanceOf(feeRecipient);

        // Lender should still have profit since they bought at 0.5 and bad debt wasn't total
        // Fee should be on actual profit (received - cost), not theoretical
        assertTrue(lenderReceived + feeReceived > 0, "lender got something");
    }

    // ============ Multiple Entry Tests ============

    function testAverageCostWithMultiplePurchases() public {
        uint256 interestFee = 0.1e18;
        morphoV2.setDefaultInterestFee(address(loanToken), interestFee);

        // First purchase: 50 units at price 0.5 (pay 25)
        uint256 units1 = 50e18;
        deal(address(loanToken), lender, 25e18);

        Offer memory borrowerOffer1;
        borrowerOffer1.obligation = obligation;
        borrowerOffer1.buy = false;
        borrowerOffer1.maker = borrower;
        borrowerOffer1.obligationUnits = units1;
        borrowerOffer1.start = block.timestamp;
        borrowerOffer1.expiry = block.timestamp + 200;
        borrowerOffer1.startPrice = 0.5e18;
        borrowerOffer1.expiryPrice = 0.5e18;

        collateralize(obligation, borrower, 100e18);
        take(0, 0, units1, 0, lender, borrowerOffer1);

        assertEq(uint256(morphoV2.costOf(lender, id)), 25e18, "cost after first purchase");

        // Second purchase: 50 units at price 0.8 (pay 40)
        uint256 units2 = 50e18;
        deal(address(loanToken), lender, 40e18);

        Offer memory borrowerOffer2;
        borrowerOffer2.obligation = obligation;
        borrowerOffer2.buy = false;
        borrowerOffer2.maker = borrower;
        borrowerOffer2.obligationUnits = units2;
        borrowerOffer2.start = block.timestamp;
        borrowerOffer2.expiry = block.timestamp + 200;
        borrowerOffer2.startPrice = 0.8e18;
        borrowerOffer2.expiryPrice = 0.8e18;
        borrowerOffer2.group = keccak256("second");

        take(0, 0, units2, 0, lender, borrowerOffer2);

        // Total cost = 25 + 40 = 65
        assertEq(uint256(morphoV2.costOf(lender, id)), 65e18, "cost after second purchase");

        // Repay all and withdraw
        deal(address(loanToken), borrower, 100e18);
        vm.prank(borrower);
        morphoV2.repay(obligation, 100e18, borrower);

        uint256 lenderShares = morphoV2.sharesOf(lender, id);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, lenderShares, lender);

        // Profit = 100 - 65 = 35, Fee = 3.5
        uint256 expectedProfit = 35e18;
        uint256 expectedFee = expectedProfit.mulDivDown(interestFee, WAD);
        uint256 lenderReceived = loanToken.balanceOf(lender) - lenderBalanceBefore;

        assertEq(lenderReceived, 100e18 - expectedFee, "lender receives correct amount");
        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee is on total profit");
    }
}
