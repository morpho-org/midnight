// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, DEFAULT_TICK_SPACING} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";

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

    Market internal market;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeClaimer = makeAddr("feeClaimer");

    function setUp() public override {
        super.setUp();

        vm.warp(block.timestamp + 1000 days); // to be able to come back in time enough

        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 1 days; // TTM = 1 day (exactly at breakpoint)
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);

        id = toId(market);

        lenderOffer.market = market;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 200;

        borrowerOffer.market = market;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.expiry = block.timestamp + 200;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        midnight.setFeeClaimer(feeClaimer);
    }

    function testBuyUnits(uint256 tradingFee, uint256 sellerTick, uint256 units) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        midnight.touchMarket(market);
        midnight.setMarketTickSpacing(id, 1);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableTradingFee(address(loanToken)), expectedFee, "claimable trading fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testSellUnits(uint256 tradingFee, uint256 buyerTick, uint256 units) public {
        units = bound(units, 0, MAX_DEBT);
        buyerTick = bound(buyerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - tradingFee;
        uint256 expectedBuyerAssets = units.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, borrower, lenderOffer);

        assertEq(midnight.claimableTradingFee(address(loanToken)), expectedFee, "claimable trading fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testDefaultTradingFee(uint256 units, uint256 sellerTick, uint256 tradingFee) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee = bound(tradingFee, 0, maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableTradingFee(address(loanToken)), expectedFee, "claimable trading fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testSevenDayTtmTradingFee(
        uint256 units,
        uint256 sellerTick,
        uint256 tradingFee1Day,
        uint256 tradingFee7Days
    ) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee1Day = bound(tradingFee1Day, 0, maxTradingFee(1)) / 1e12 * 1e12;
        tradingFee7Days = bound(tradingFee7Days, tradingFee1Day, maxTradingFee(2)) / 1e12 * 1e12;

        market.maturity = block.timestamp + 3 days;

        // Set fees at breakpoints for linear interpolation (3 days is between 1 and 7 days)
        // Must be set before touchMarket, which snapshots defaultFees at creation time.
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee1Day);
        midnight.setDefaultTradingFee(address(loanToken), 2, tradingFee7Days);

        id = midnight.touchMarket(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = midnight.tradingFee(id, market.maturity - block.timestamp);

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableTradingFee(address(loanToken)), expectedFee, "claimable trading fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testPostMaturityTradingFee(uint256 units, uint256 sellerTick, uint256 tradingFee0Day, uint256 maturity)
        public
    {
        units = bound(units, 1, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee0Day = bound(tradingFee0Day, 0, maxTradingFee(0)) / 1e12 * 1e12;
        maturity = bound(maturity, 0, block.timestamp - 1);
        market.maturity = maturity;
        id = toId(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;

        midnight.setDefaultTradingFee(address(loanToken), 0, tradingFee0Day);
        borrowerOffer.tick = sellerTick;

        collateralize(market, borrower, MAX_DEBT);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, lender, borrowerOffer);
    }

    function testEarlyTradingFee(uint256 units, uint256 sellerTick, uint256 tradingFee360Days, uint256 maturity)
        public
    {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        tradingFee360Days = bound(tradingFee360Days, 0, maxTradingFee(6)) / 1e12 * 1e12;
        maturity = bound(maturity, block.timestamp + 360 days, block.timestamp + 36500 days);

        market.maturity = maturity;
        id = toId(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;

        midnight.setDefaultTradingFee(address(loanToken), 6, tradingFee360Days);
        borrowerOffer.tick = sellerTick;

        uint256 tradingFee = tradingFee360Days;

        uint256 buyerPrice = sellerPrice + tradingFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableTradingFee(address(loanToken)), expectedFee, "claimable trading fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testClaimTradingFee(uint256 tradingFee, uint256 units, uint256 withdrawAmount) public {
        units = bound(units, 1, MAX_DEBT);
        tradingFee = bound(tradingFee, 1e12, maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);

        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        uint256 fee = midnight.claimableTradingFee(address(loanToken));
        vm.assume(fee > 0);
        withdrawAmount = bound(withdrawAmount, 1, fee);
        address receiver = makeAddr("receiver");

        vm.prank(feeClaimer);
        midnight.claimTradingFee(address(loanToken), withdrawAmount, receiver);

        assertEq(loanToken.balanceOf(receiver), withdrawAmount, "receiver balance");
        assertEq(midnight.claimableTradingFee(address(loanToken)), fee - withdrawAmount, "remaining fee");
    }

    function testClaimTradingFeeOnlyFeeClaimer(address caller) public {
        vm.assume(caller != feeClaimer);
        vm.prank(caller);
        vm.expectRevert(IMidnight.OnlyFeeClaimer.selector);
        midnight.claimTradingFee(address(loanToken), 0, caller);
    }

    function testClaimTradingFeeExcessReverts() public {
        uint256 tradingFee = maxTradingFee(1) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = 0;

        collateralize(market, borrower, MAX_DEBT);
        take(1000, lender, borrowerOffer);

        uint256 fee = midnight.claimableTradingFee(address(loanToken));

        vm.prank(feeClaimer);
        vm.expectRevert();
        midnight.claimTradingFee(address(loanToken), fee + 1, feeClaimer);
    }

    function testTradingFeesAccumulate() public {
        uint256 tradingFee = maxTradingFee(1) / 1e12 * 1e12;
        midnight.setDefaultTradingFee(address(loanToken), 1, tradingFee);
        borrowerOffer.tick = 0;
        borrowerOffer.group = keccak256("g1");

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(1000, lender, borrowerOffer);
        uint256 feeAfterFirst = midnight.claimableTradingFee(address(loanToken));

        borrowerOffer.group = keccak256("g2");
        take(1000, lender, borrowerOffer);
        uint256 feeAfterSecond = midnight.claimableTradingFee(address(loanToken));

        assertEq(feeAfterSecond, feeAfterFirst * 2, "fees accumulated");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, feeAfterSecond, "contract balance increase");
    }
}
