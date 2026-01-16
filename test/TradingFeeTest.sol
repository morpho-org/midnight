// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 1 days; // TTM = 1 day (exactly at breakpoint)
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

    function testBuyBuyerAssets(uint256 buyerAssets, uint256 sellerPrice, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, buyerPrice) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 0.05 ether) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 0.5 ether) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 0.05 ether) / 1e12 * 1e12;
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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
        tradingFee = bound(tradingFee, 0, 1 ether - sellerPrice) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFeeActivated(address(loanToken), true);
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSevenDayTtmFee(uint256 buyerAssets, uint256 sellerPrice, uint256 fee1Day, uint256 fee7Days) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        fee1Day = bound(fee1Day, 0, (1 ether - sellerPrice) / 2) / 1e12 * 1e12;
        fee7Days = bound(fee7Days, fee1Day, (1 ether - sellerPrice) / 2) / 1e12 * 1e12;

        obligation.maturity = block.timestamp + 3 days;
        id = keccak256(abi.encode(obligation));
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        // Set fees at breakpoints for linear interpolation (3 days is between 1 and 7 days)
        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, fee1Day);
        morphoV2.setObligationTradingFee(id, 2, fee7Days);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        // Calculate expected interpolated fee: fee = fee1Day + (fee7Days - fee1Day) * (3 - 1) / (7 - 1)
        uint256 tradingFee = fee1Day + (fee7Days - fee1Day) * 2 / 6;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerPriceTooHighFees() public {
        uint256 tradingFee = 0.6 ether;
        uint256 sellerPrice = 0.5 ether;

        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 1, tradingFee);
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

    function testPostMaturityFee(uint256 buyerAssets, uint256 sellerPrice, uint256 fee0Day, uint256 maturity) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        fee0Day = bound(fee0Day, 0, (1 ether - sellerPrice) / 2) / 1e12 * 1e12;
        maturity = bound(maturity, 0, block.timestamp - 1);
        obligation.maturity = maturity;
        id = keccak256(abi.encode(obligation));
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 0, fee0Day);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 tradingFee = fee0Day;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testEarlyFee(uint256 buyerAssets, uint256 sellerPrice, uint256 fee180Days, uint256 maturity) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerPrice = bound(sellerPrice, 0.5 ether, 1 ether);
        fee180Days = bound(fee180Days, 0, (1 ether - sellerPrice) / 2) / 1e12 * 1e12;
        maturity = bound(maturity, block.timestamp + 180 days, block.timestamp + 36500 days);

        obligation.maturity = maturity;
        id = keccak256(abi.encode(obligation));
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        morphoV2.setObligationTradingFeeActivated(id, true);
        morphoV2.setObligationTradingFee(id, 5, fee180Days);
        borrowerOffer.startPrice = sellerPrice;
        borrowerOffer.expiryPrice = sellerPrice;

        uint256 tradingFee = fee180Days;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
