// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

// The maximum debt from a trade must fit in uint128, and the required collateral (debt / lltv)
// must also fit in uint128. With lltv = 0.75: collateral = debt * 4/3.
// So debt <= type(uint128).max * 3/4.
uint256 constant MAX_DEBT = MAX_TEST_AMOUNT * 3 / 4;

uint256 constant MIN_SELLER_PRICE = 0.5e18;

// In sell tests, sellerPrice = buyerPrice - tradingFee, so the minimum effective price is
// MIN_SELLER_PRICE - maxTradingFee. Price conversion amplifies assets by up to WAD / minPrice.
// Combined with the collateral constraint: assets * WAD / minPrice * 4/3 <= type(uint128).max.
// Uses 0.005e18 which is maxTradingFee(6), the biggest max trading fee.
uint256 constant MAX_ASSETS = MAX_TEST_AMOUNT * (MIN_SELLER_PRICE - 0.005e18) / WAD * 3 / 4;

contract TradingFeeTest is BaseTest {
    using UtilsLib for uint256;

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
        lenderOffer.expiry = block.timestamp + 200;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        midnight.setTradingFeeRecipient(feeRecipient);
    }

    function testBuyObligationUnits(uint256 tradingFee, uint256 sellerTick, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellObligationUnits(uint256 tradingFee, uint256 buyerTick, uint256 obligationUnits) public {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        buyerTick = bound(buyerTick, 0, TICK_RANGE);
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testDefaultFee(uint256 obligationUnits, uint256 sellerTick, uint256 tradingFee) public {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSevenDayTtmFee(uint256 obligationUnits, uint256 sellerTick, uint256 fee1Day, uint256 fee7Days) public {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        fee1Day = bound(fee1Day, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        fee7Days = bound(fee7Days, fee1Day, midnight.maxTradingFee(2)) / 1e12 * 1e12;

        obligation.maturity = block.timestamp + 3 days;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        // Set fees at breakpoints for linear interpolation (3 days is between 1 and 7 days)
        midnight.setDefaultTradingFee(address(loanToken), 1, fee1Day);
        midnight.setDefaultTradingFee(address(loanToken), 2, fee7Days);
        borrowerOffer.tick = sellerTick;

        // Calculate expected interpolated fee: fee = fee1Day + (fee7Days - fee1Day) * (3 - 1) / (7 - 1)
        uint256 tradingFee = fee1Day + (fee7Days - fee1Day) * 2 / 6;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testPostMaturityFee(uint256 obligationUnits, uint256 sellerTick, uint256 fee0Day, uint256 maturity)
        public
    {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        fee0Day = bound(fee0Day, 0, midnight.maxTradingFee(0)) / 1e12 * 1e12;
        maturity = bound(maturity, 0, block.timestamp - 1);
        obligation.maturity = maturity;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        midnight.setDefaultTradingFee(address(loanToken), 0, fee0Day);
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = fee0Day;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testEarlyFee(uint256 obligationUnits, uint256 sellerTick, uint256 fee360Days, uint256 maturity) public {
        obligationUnits = bound(obligationUnits, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, TICK_RANGE);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        fee360Days = bound(fee360Days, 0, midnight.maxTradingFee(6)) / 1e12 * 1e12;
        maturity = bound(maturity, block.timestamp + 360 days, block.timestamp + 36500 days);

        obligation.maturity = maturity;
        id = toId(obligation);
        lenderOffer.obligation = obligation;
        borrowerOffer.obligation = obligation;

        midnight.setDefaultTradingFee(address(loanToken), 6, fee360Days);
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = fee360Days;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        collateralize(obligation, borrower, MAX_DEBT);
        take(obligationUnits, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
