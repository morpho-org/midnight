// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, DEFAULT_TICK_SPACING} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

// The maximum debt from a take must fit in uint128, and the required collateral (debt / lltv)
// must also fit in uint128. With lltv = 0.75: collateral = debt * 4/3.
// So debt <= type(uint128).max * 3/4.
uint256 constant MAX_DEBT = MAX_TEST_AMOUNT * 3 / 4;

uint256 constant MIN_SELLER_PRICE = 0.5e18;

// In sell tests, sellerPrice = buyerPrice - settlementFee, so the minimum effective price is
// MIN_SELLER_PRICE - maxSettlementFee. Price conversion amplifies assets by up to WAD / minPrice.
// Combined with the collateral constraint: assets * WAD / minPrice * 4/3 <= type(uint128).max.
// Uses 0.005e18 which is maxSettlementFee(6), the biggest max settlement fee.
uint256 constant MAX_ASSETS = MAX_TEST_AMOUNT * (MIN_SELLER_PRICE - 0.005e18) / WAD * 3 / 4;

contract SettlementFeeTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeClaimer = makeAddr("feeClaimer");

    function setUp() public override {
        super.setUp();

        vm.warp(vm.getBlockTimestamp() + 1000 days); // to be able to come back in time enough

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 1 days; // TTM = 1 day (exactly at breakpoint)
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
        lenderOffer.ratifier = address(dummyRatifier);
        lenderOffer.start = vm.getBlockTimestamp();
        lenderOffer.expiry = vm.getBlockTimestamp() + 200;

        borrowerOffer.market = market;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.ratifier = address(dummyRatifier);
        borrowerOffer.expiry = vm.getBlockTimestamp() + 200;

        deal(address(loanToken), address(lender), MAX_TEST_AMOUNT * 10000);

        midnight.setFeeClaimer(feeClaimer);
    }

    function testBuyUnits(uint256 settlementFee, uint256 sellerTick, uint256 units) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK);
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        settlementFee = bound(settlementFee, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);
        midnight.touchMarket(market);
        midnight.setMarketTickSpacing(id, 1);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + settlementFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableSettlementFee(address(loanToken)), expectedFee, "claimable settlement fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testSellUnits(uint256 settlementFee, uint256 buyerTick, uint256 units) public {
        units = bound(units, 0, MAX_DEBT);
        buyerTick = bound(buyerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 buyerPrice = TickLib.tickToPrice(buyerTick);
        vm.assume(buyerPrice >= MIN_SELLER_PRICE);
        settlementFee = bound(settlementFee, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);
        lenderOffer.tick = buyerTick;

        uint256 sellerPrice = buyerPrice - settlementFee;
        uint256 expectedBuyerAssets = units.mulDivDown(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, borrower, lenderOffer);

        assertEq(midnight.claimableSettlementFee(address(loanToken)), expectedFee, "claimable settlement fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testDefaultSettlementFee(uint256 units, uint256 sellerTick, uint256 settlementFee) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        settlementFee = bound(settlementFee, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);
        borrowerOffer.tick = sellerTick;

        uint256 buyerPrice = sellerPrice + settlementFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableSettlementFee(address(loanToken)), expectedFee, "claimable settlement fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testSevenDayTtmSettlementFee(
        uint256 units,
        uint256 sellerTick,
        uint256 settlementFee1Day,
        uint256 settlementFee7Days
    ) public {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        settlementFee1Day = bound(settlementFee1Day, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        settlementFee7Days = bound(settlementFee7Days, settlementFee1Day, maxSettlementFee(2)) / 1e12 * 1e12;

        market.maturity = vm.getBlockTimestamp() + 3 days;

        // Set fees at breakpoints for linear interpolation (3 days is between 1 and 7 days)
        // Must be set before touchMarket, which snapshots defaultFees at creation time.
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee1Day);
        midnight.setDefaultSettlementFee(address(loanToken), 2, settlementFee7Days);

        id = midnight.touchMarket(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;
        borrowerOffer.tick = sellerTick;

        uint256 settlementFee = midnight.settlementFee(id, market.maturity - vm.getBlockTimestamp());

        uint256 buyerPrice = sellerPrice + settlementFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableSettlementFee(address(loanToken)), expectedFee, "claimable settlement fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testPostMaturitySettlementFee(
        uint256 units,
        uint256 sellerTick,
        uint256 settlementFee0Day,
        uint256 maturity
    ) public {
        units = bound(units, 1, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        settlementFee0Day = bound(settlementFee0Day, 0, maxSettlementFee(0)) / 1e12 * 1e12;
        maturity = bound(maturity, 0, vm.getBlockTimestamp() - 1);
        market.maturity = maturity;
        id = toId(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;

        midnight.setDefaultSettlementFee(address(loanToken), 0, settlementFee0Day);
        borrowerOffer.tick = sellerTick;

        collateralize(market, borrower, MAX_DEBT);

        vm.expectRevert(IMidnight.CannotIncreaseDebtPostMaturity.selector);
        take(units, lender, borrowerOffer);
    }

    function testEarlySettlementFee(uint256 units, uint256 sellerTick, uint256 settlementFee360Days, uint256 maturity)
        public
    {
        units = bound(units, 0, MAX_DEBT);
        sellerTick = bound(sellerTick, 0, MAX_TICK / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;
        uint256 sellerPrice = TickLib.tickToPrice(sellerTick);
        vm.assume(sellerPrice >= MIN_SELLER_PRICE);
        settlementFee360Days = bound(settlementFee360Days, 0, maxSettlementFee(6)) / 1e12 * 1e12;
        maturity = bound(maturity, vm.getBlockTimestamp() + 360 days, vm.getBlockTimestamp() + 36500 days);

        market.maturity = maturity;
        id = toId(market);
        lenderOffer.market = market;
        borrowerOffer.market = market;

        midnight.setDefaultSettlementFee(address(loanToken), 6, settlementFee360Days);
        borrowerOffer.tick = sellerTick;

        uint256 settlementFee = settlementFee360Days;

        uint256 buyerPrice = sellerPrice + settlementFee;
        vm.assume(buyerPrice <= WAD);
        uint256 expectedBuyerAssets = units.mulDivUp(buyerPrice, WAD);
        uint256 expectedSellerAssets = units.mulDivUp(sellerPrice, WAD);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        assertEq(midnight.claimableSettlementFee(address(loanToken)), expectedFee, "claimable settlement fee");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, expectedFee, "contract balance increase");
    }

    function testClaimSettlementFee(uint256 settlementFee, uint256 units, uint256 withdrawAmount) public {
        units = bound(units, 1, MAX_DEBT);
        settlementFee = bound(settlementFee, 1e12, maxSettlementFee(1)) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);

        collateralize(market, borrower, MAX_DEBT);
        take(units, lender, borrowerOffer);

        uint256 fee = midnight.claimableSettlementFee(address(loanToken));
        vm.assume(fee > 0);
        withdrawAmount = bound(withdrawAmount, 1, fee);
        address receiver = makeAddr("receiver");

        vm.prank(feeClaimer);
        midnight.claimSettlementFee(address(loanToken), withdrawAmount, receiver);

        assertEq(loanToken.balanceOf(receiver), withdrawAmount, "receiver balance");
        assertEq(midnight.claimableSettlementFee(address(loanToken)), fee - withdrawAmount, "remaining fee");
    }

    function testClaimSettlementFeeOnlyFeeClaimer(address caller) public {
        vm.assume(caller != feeClaimer);
        vm.prank(caller);
        vm.expectRevert(IMidnight.OnlyFeeClaimer.selector);
        midnight.claimSettlementFee(address(loanToken), 0, caller);
    }

    function testClaimSettlementFeeExcessReverts() public {
        uint256 settlementFee = maxSettlementFee(1) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);
        borrowerOffer.tick = 0;

        collateralize(market, borrower, MAX_DEBT);
        take(1000, lender, borrowerOffer);

        uint256 fee = midnight.claimableSettlementFee(address(loanToken));

        vm.prank(feeClaimer);
        vm.expectRevert();
        midnight.claimSettlementFee(address(loanToken), fee + 1, feeClaimer);
    }

    function testSettlementFeesAccumulate() public {
        uint256 settlementFee = maxSettlementFee(1) / 1e12 * 1e12;
        midnight.setDefaultSettlementFee(address(loanToken), 1, settlementFee);
        borrowerOffer.tick = 0;
        borrowerOffer.group = keccak256("g1");

        uint256 balanceBefore = loanToken.balanceOf(address(midnight));
        collateralize(market, borrower, MAX_DEBT);
        take(1000, lender, borrowerOffer);
        uint256 feeAfterFirst = midnight.claimableSettlementFee(address(loanToken));

        borrowerOffer.group = keccak256("g2");
        take(1000, lender, borrowerOffer);
        uint256 feeAfterSecond = midnight.claimableSettlementFee(address(loanToken));

        assertEq(feeAfterSecond, feeAfterFirst * 2, "fees accumulated");
        assertEq(loanToken.balanceOf(address(midnight)) - balanceBefore, feeAfterSecond, "contract balance increase");
    }
}
