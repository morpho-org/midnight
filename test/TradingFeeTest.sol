// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
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
        obligation.maturity = block.timestamp + 100;
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
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    /// @dev Helper to set a constant trading fee (min=max=fee)
    function setConstantObligationFee(bytes32 _id, uint64 fee) internal {
        morphoV2.setObligationTradingFee(_id, true, fee, 0, fee);
    }

    /// @dev Helper to set a constant default trading fee (min=max=fee)
    function setConstantDefaultFee(address loanToken_, uint64 fee) internal {
        morphoV2.setDefaultTradingFee(loanToken_, true, fee, 0, fee);
    }

    function testBuyBuyerAssets(uint256 buyerAssets, uint256 sellerPrice, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        setConstantObligationFee(id, uint64(tradingFee));
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellBuyerAssets(uint256 tradingFee, uint256 buyerPrice, uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, buyerPrice);
        setConstantObligationFee(id, uint64(tradingFee));
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(
            loanToken.balanceOf(feeRecipient), expectedFee, buyerAssets / 1e6 + 100, "fee recipient balance"
        );
    }

    function testBuySellerAssets(uint256 tradingFee, uint256 sellerPrice, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        setConstantObligationFee(id, uint64(tradingFee));
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, sellerAssets, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellSellerAssets(uint256 tradingFee, uint256 buyerPrice, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.05 ether);
        setConstantObligationFee(id, uint64(tradingFee));
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, sellerAssets, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationUnits(uint256 tradingFee, uint256 sellerPrice, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.01 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        setConstantObligationFee(id, uint64(tradingFee));
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationUnits(uint256 tradingFee, uint256 buyerPrice, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.5 ether);
        setConstantObligationFee(id, uint64(tradingFee));
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationShares(uint256 tradingFee, uint256 sellerPrice, uint256 obligationShares) public {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        setConstantObligationFee(id, uint64(tradingFee));
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationShares(uint256 tradingFee, uint256 buyerPrice, uint256 obligationShares) public {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        buyerPrice = bound(buyerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 0.05 ether);
        setConstantObligationFee(id, uint64(tradingFee));
        lenderOffer.startPrice = buyerPrice;
        lenderOffer.expiryPrice = buyerPrice;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testDefaultFee(uint256 buyerAssets, uint256 sellerPrice, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice);
        setConstantDefaultFee(address(loanToken), uint64(tradingFee));
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testTtmDependentFee(uint256 buyerAssets, uint256 sellerPrice) public {
        buyerAssets = bound(buyerAssets, 1e15, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 0.95 ether);

        // Set up obligation with 7 days maturity
        obligation.maturity = block.timestamp + 7 days;
        id = keccak256(abi.encode(obligation));
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        // Set fee with duration = 14 days, so at ttm=7 days, fee = (max+min)/2 (midpoint of linear ramp)
        uint64 minFee = 0.01 ether;
        uint64 maxFee = 0.05 ether;
        uint64 duration = 14 days;
        morphoV2.setObligationTradingFee(id, true, minFee, duration, maxFee);

        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        // At ttm=7 days (duration/2), fee should be (max+min)/2 = 0.03 ether
        uint256 expectedTradingFee = (uint256(maxFee) + uint256(minFee)) / 2;
        uint256 buyerPrice = sellerPrice + expectedTradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerPriceTooHighFees() public {
        uint64 tradingFee = 0.6 ether;
        uint256 sellerPrice = 0.5 ether;

        setConstantObligationFee(id, tradingFee);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);

        vm.expectRevert("cannot trade at price above one");
        take(MAX_TEST_AMOUNT, 0, 0, 0, lender, borrowerOffer);
    }

    function testBuyerPriceTooHighOfferPrice() public {
        uint256 offerPrice = 1.5 ether;

        lenderOffer.startPrice = offerPrice;
        lenderOffer.expiryPrice = offerPrice;

        vm.expectRevert("cannot trade at price above one");
        take(MAX_TEST_AMOUNT, 0, 0, 0, borrower, lenderOffer);
    }
}
