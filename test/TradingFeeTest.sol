// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MAX_FEE} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using UtilsLib for uint256;

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();

        vm.warp(block.timestamp + 1000 days); // to be able to come back in time enough

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 1 days; // TTM = 1 day (exactly at breakpoint)
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
        lenderOffer.expiry = block.timestamp + 200;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    function testBuyBuyerAssets(uint256 buyerAssets, uint256 sellerTick, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellBuyerAssets(uint256 tradingFee, uint256 buyerTick, uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        buyerTick = bound(buyerTick, 0, TICK_RANGE);
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, buyerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(
            loanToken.balanceOf(feeRecipient), expectedFee, buyerAssets / 1e6 + 100, "fee recipient balance"
        );
    }

    function testBuySellerAssets(uint256 tradingFee, uint256 sellerTick, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, sellerAssets, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellSellerAssets(uint256 tradingFee, uint256 buyerTick, uint256 sellerAssets) public {
        sellerAssets = bound(sellerAssets, 0, MAX_TEST_AMOUNT);
        buyerTick = bound(buyerTick, 0, TICK_RANGE);
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, buyerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, sellerAssets, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationUnits(uint256 tradingFee, uint256 sellerTick, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.01e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 10);
        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationUnits(uint256 tradingFee, uint256 buyerTick, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        buyerTick = bound(buyerTick, 0, TICK_RANGE);
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, buyerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyObligationShares(uint256 tradingFee, uint256 sellerTick, uint256 obligationShares) public {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationShares(uint256 tradingFee, uint256 buyerTick, uint256 obligationShares) public {
        obligationShares = bound(obligationShares, 0, MAX_TEST_AMOUNT);
        buyerTick = bound(buyerTick, 0, TICK_RANGE);
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, buyerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationShares.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationShares.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testDefaultFee(uint256 buyerAssets, uint256 sellerTick, uint256 tradingFee) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        tradingFee = bound(tradingFee, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        morphoV2.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSevenDayTtmFee(uint256 buyerAssets, uint256 sellerTick, uint256 fee1Day, uint256 fee7Days) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        fee1Day = bound(fee1Day, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        fee7Days = bound(fee7Days, fee1Day, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;

        obligation.maturity = block.timestamp + 3 days;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        // Set fees at breakpoints for linear interpolation (3 days is between 1 and 7 days)
        morphoV2.setDefaultTradingFee(address(loanToken), 1, fee1Day);
        morphoV2.setDefaultTradingFee(address(loanToken), 2, fee7Days);
        borrowerOffer.tick = sellerTick;

        // Calculate expected interpolated fee: fee = fee1Day + (fee7Days - fee1Day) * (3 - 1) / (7 - 1)
        uint256 tradingFee = fee1Day + (fee7Days - fee1Day) * 2 / 6;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testPostMaturityFee(uint256 buyerAssets, uint256 sellerTick, uint256 fee0Day, uint256 maturity) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        fee0Day = bound(fee0Day, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        maturity = bound(maturity, 0, block.timestamp - 1);
        obligation.maturity = maturity;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        morphoV2.setDefaultTradingFee(address(loanToken), 0, fee0Day);
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = fee0Day;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testEarlyFee(uint256 buyerAssets, uint256 sellerTick, uint256 fee180Days, uint256 maturity) public {
        buyerAssets = bound(buyerAssets, 0, MAX_TEST_AMOUNT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= 0.5e18);
        fee180Days = bound(fee180Days, 0, min(MAX_FEE, 1 ether - sellerPrice)) / 1e12 * 1e12;
        maturity = bound(maturity, block.timestamp + 180 days, block.timestamp + 36500 days);

        obligation.maturity = maturity;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        morphoV2.setDefaultTradingFee(address(loanToken), 5, fee180Days);
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = fee180Days;

        uint256 buyerPrice = sellerPrice + tradingFee;
        uint256 expectedSellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_TEST_AMOUNT * 3);
        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
