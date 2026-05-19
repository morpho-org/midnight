// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {IEcrecoverRatifier, Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {Midnight} from "../src/Midnight.sol";
import {WAD, CALLBACK_SUCCESS, MAX_CONTINUOUS_FEE} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {IBuyCallback, ISellCallback} from "../src/interfaces/ICallbacks.sol";
import {IRatifier} from "../src/interfaces/IRatifier.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    Offer internal otherLenderOffer;
    Offer internal otherBorrowerOffer;

    uint256 internal maxAssets = 1e33; // to refine.

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 100;
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
        market.rcfThreshold = 0;

        id = midnight.touchMarket(market);
        midnight.setMarketTickSpacing(id, 1);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.market = market;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.ratifier = address(ecrecoverRatifier);
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.maxUnits = type(uint256).max;
        otherLenderOffer.market = market;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = MAX_TICK;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.market = market;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.ratifier = address(ecrecoverRatifier);
        otherBorrowerOffer.maxUnits = type(uint256).max;
        otherBorrowerOffer.market = market;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;
    }

    // tests.

    // path 1: Lender enters + borrower enters.

    function testBuy1(uint256 units, uint256 tick) public {
        units = bound(units, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedAssets = units.mulDivUp(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(market, borrower, units);

        take(units, lender, borrowerOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, borrower), units, "borrower debt");
        assertEq(midnight.totalUnits(id), units, "total units");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(borrower, borrowerOffer.group), units, "consumed");
    }

    function testSell1(uint256 units, uint256 tick) public {
        units = bound(units, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedAssets = units.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(market, borrower, units);

        take(units, borrower, lenderOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, borrower), units, "borrower debt");
        assertEq(midnight.totalUnits(id), units, "total units");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(lender, lenderOffer.group), units, "consumed");
    }

    // path 2: Lender enters + lender exits.

    function testBuy2(uint256 units, uint256 tick, uint256 otherLenderUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = units.mulDivDown(price, WAD);
        otherLenderUnits = bound(otherLenderUnits, units, max(units, maxAssets));
        setupOtherUsers(market, otherLenderUnits);
        uint256 actualOtherLenderCredit = midnight.creditOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        otherLenderOffer.buy = false;
        otherLenderOffer.maxUnits = type(uint256).max;
        otherLenderOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, lender, otherLenderOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), actualOtherLenderCredit - units, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testSell2(uint256 units, uint256 tick, uint256 otherLenderUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = units.mulDivDown(price, WAD);
        otherLenderUnits = bound(otherLenderUnits, units, max(units, maxAssets));
        setupOtherUsers(market, otherLenderUnits);
        uint256 actualOtherLenderCredit = midnight.creditOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, otherLender, lenderOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), actualOtherLenderCredit - units, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    // Lender sells more than their balance, crossing to borrower.
    function testCrossTopDown(uint256 units, uint256 otherLenderUnits) public {
        otherLenderUnits = bound(otherLenderUnits, 1, maxAssets - 1);
        units = bound(units, otherLenderUnits + 1, maxAssets);
        setupOtherUsers(market, otherLenderUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(market, otherLender, units);
        otherLenderOffer.tick = MAX_TICK;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, lender, otherLenderOffer);

        // otherLender crossed from lender to borrower.
        assertEq(midnight.creditOf(id, otherLender), 0, "otherLender credit");
        assertEq(midnight.debtOf(id, otherLender), units - otherLenderCredit, "otherLender debt");
        assertEq(midnight.creditOf(id, lender), units, "lender credit");
        assertEq(midnight.totalUnits(id), totalUnitsBefore + units - otherLenderCredit, "total units");
    }

    // path 3: Borrower exits + borrower enters.

    function testBuy3(uint256 units, uint256 tick, uint256 existingUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        existingUnits = bound(existingUnits, units, max(units, maxAssets));
        setupOtherUsers(market, existingUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(market, borrower, units);
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), otherBorrower, units.mulDivUp(price, WAD));
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, otherBorrower, borrowerOffer);

        assertEq(midnight.debtOf(id, borrower), units, "borrower debt");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testSell3(uint256 units, uint256 tick, uint256 existingUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        existingUnits = bound(existingUnits, units, max(units, maxAssets));
        setupOtherUsers(market, existingUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(market, borrower, units);
        otherBorrowerOffer.maxUnits = type(uint256).max;
        otherBorrowerOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(id, borrower), units, "borrower debt");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    // Borrower buys more than their debt, crossing to lender.
    function testCrossBottomUp(uint256 units, uint256 otherUnits) public {
        otherUnits = bound(otherUnits, 1, maxAssets - 1);
        units = bound(units, otherUnits + 1, maxAssets);
        setupOtherUsers(market, otherUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), otherBorrower, units.mulDivUp(price, WAD));
        collateralize(market, borrower, units);
        borrowerOffer.tick = MAX_TICK;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(units, otherBorrower, borrowerOffer);

        // otherBorrower crossed from borrower to lender.
        assertEq(midnight.debtOf(id, otherBorrower), 0, "otherBorrower debt");
        assertEq(midnight.creditOf(id, otherBorrower), units - otherBorrowerDebt, "otherBorrower credit");
        assertEq(midnight.debtOf(id, borrower), units, "borrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore + units - otherBorrowerDebt, "total units");
    }

    // path 4: Borrower exits + lender exits.

    function testBuy4(uint256 units, uint256 tick, uint256 existingUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        existingUnits = bound(existingUnits, units, max(units, maxAssets));
        setupOtherUsers(market, existingUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherLenderOffer.maxUnits = type(uint256).max;
        otherLenderOffer.tick = tick;
        deal(address(loanToken), otherBorrower, buyerAssets);

        take(units, otherBorrower, otherLenderOffer);

        assertEq(midnight.creditOf(id, otherLender), otherLenderCredit - units, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - units, "total units");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
    }

    function testSell4(uint256 units, uint256 tick, uint256 existingUnits) public {
        units = bound(units, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = units.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, units, max(units, maxAssets));
        setupOtherUsers(market, existingUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherBorrowerOffer.maxUnits = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(units, otherLender, otherBorrowerOffer);

        assertEq(midnight.creditOf(id, otherLender), otherLenderCredit - units, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - units, "total units");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
    }

    function testBuy1PostMaturity() public {
        uint256 units = 100;
        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.maxUnits = units;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, lender, borrowerOffer);
    }

    function testSell1PostMaturity() public {
        uint256 units = 100;
        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.maxUnits = units;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, borrower, lenderOffer);
    }

    function testBuy2PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);
        assertEq(midnight.creditOf(id, otherLender), units, "other lender credit");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertTrue(midnight.isHealthy(market, id, otherLender), "other lender healthy");
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        otherLenderOffer.expiry = timestamp;
        otherLenderOffer.maxUnits = units;
        deal(address(loanToken), lender, units);

        take(units, lender, otherLenderOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), 0, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testSell2PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);
        assertEq(midnight.creditOf(id, otherLender), units, "other lender credit");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertTrue(midnight.isHealthy(market, id, otherLender), "other lender healthy");
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.maxUnits = units;
        deal(address(loanToken), lender, units);

        take(units, otherLender, lenderOffer);

        assertEq(midnight.creditOf(id, lender), units, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), 0, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testBuy3PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.maxUnits = units;
        deal(address(loanToken), otherBorrower, units);
        collateralize(market, borrower, units);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, otherBorrower, borrowerOffer);
    }

    function testSell3PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        otherBorrowerOffer.expiry = timestamp;
        otherBorrowerOffer.maxUnits = units;
        deal(address(loanToken), otherBorrower, units);
        collateralize(market, borrower, units);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, borrower, otherBorrowerOffer);
    }

    function testBuy4PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);
        assertEq(midnight.creditOf(id, otherLender), units, "other lender credit");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertTrue(midnight.isHealthy(market, id, otherLender), "other lender healthy");
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        otherLenderOffer.expiry = timestamp;
        otherLenderOffer.maxUnits = units;
        deal(address(loanToken), otherBorrower, units);

        take(units, otherBorrower, otherLenderOffer);

        assertEq(midnight.creditOf(id, otherLender), 0, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - units, "total units");
    }

    function testSell4PostMaturity() public {
        uint256 units = 100;
        setupOtherUsers(market, units);
        assertEq(midnight.creditOf(id, otherLender), units, "other lender credit");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertTrue(midnight.isHealthy(market, id, otherLender), "other lender healthy");
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        uint256 timestamp = market.maturity + 1;
        vm.warp(timestamp);
        otherBorrowerOffer.expiry = timestamp;
        otherBorrowerOffer.maxUnits = units;
        deal(address(loanToken), otherBorrower, units);

        take(units, otherLender, otherBorrowerOffer);

        assertEq(midnight.creditOf(id, otherLender), 0, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - units, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - units, "total units");
    }

    // reduceOnly tests.

    function testReduceOnlyBuySuccess(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets);
        exitUnits = bound(exitUnits, 1, existingUnits);
        setupOtherUsers(market, existingUnits);

        otherBorrowerOffer.maxUnits = exitUnits;
        otherBorrowerOffer.reduceOnly = true;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), otherBorrower, exitUnits.mulDivUp(price, WAD));
        collateralize(market, borrower, exitUnits);

        uint256 debtBefore = midnight.debtOf(id, otherBorrower);
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(exitUnits, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(id, borrower), exitUnits, "borrower debt");
        assertEq(midnight.creditOf(id, otherBorrower), 0, "otherBorrower units");
        assertEq(midnight.debtOf(id, otherBorrower), debtBefore - exitUnits, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testReduceOnlyBuyRevert(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets - 1);
        exitUnits = bound(exitUnits, existingUnits + 1, maxAssets);
        setupOtherUsers(market, existingUnits);

        otherBorrowerOffer.maxUnits = exitUnits;
        otherBorrowerOffer.reduceOnly = true;

        vm.expectRevert(IMidnight.MakerCreditOrDebtIncreased.selector);
        take(exitUnits, borrower, otherBorrowerOffer);
    }

    function testReduceOnlySellSuccess(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets);
        exitUnits = bound(exitUnits, 1, existingUnits);
        setupOtherUsers(market, existingUnits);

        otherLenderOffer.maxUnits = exitUnits;
        otherLenderOffer.reduceOnly = true;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, exitUnits.mulDivUp(price, WAD));

        uint256 creditBefore = midnight.creditOf(id, otherLender);
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(exitUnits, lender, otherLenderOffer);

        assertEq(midnight.creditOf(id, lender), exitUnits, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), creditBefore - exitUnits, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testReduceOnlySellRevert(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets - 1);
        exitUnits = bound(exitUnits, existingUnits + 1, maxAssets);
        setupOtherUsers(market, existingUnits);

        otherLenderOffer.maxUnits = exitUnits;
        otherLenderOffer.reduceOnly = true;

        vm.expectRevert(IMidnight.MakerCreditOrDebtIncreased.selector);
        take(exitUnits, lender, otherLenderOffer);
    }

    // group tests.

    function testBuyConsumed(uint256 units, uint256 offerUnits, uint256 secondRevertingTake, uint256 secondPassingTake)
        public
    {
        units = bound(units, 0, maxAssets - 1);
        offerUnits = bound(offerUnits, units, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerUnits - units + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerUnits - units);
        borrowerOffer.maxUnits = offerUnits;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerUnits);
        collateralize(market, borrower, offerUnits);

        take(units, lender, borrowerOffer);

        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        take(secondRevertingTake, lender, borrowerOffer);

        take(secondPassingTake, lender, borrowerOffer);
    }

    function testSellConsumed(uint256 units, uint256 offerUnits, uint256 secondRevertingTake, uint256 secondPassingTake)
        public
    {
        units = bound(units, 0, maxAssets - 1);
        offerUnits = bound(offerUnits, units, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerUnits - units + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerUnits - units);
        lenderOffer.maxUnits = offerUnits;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerUnits);
        collateralize(market, borrower, offerUnits);

        take(units, borrower, lenderOffer);

        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        take(secondRevertingTake, borrower, lenderOffer);

        take(secondPassingTake, borrower, lenderOffer);
    }

    function testBuyGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.maxUnits = firstFill + secondFill;
        borrowerOffer.tick = MAX_TICK;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.market.maturity = market.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(market, borrower, firstFill);
        collateralize(borrowerOffer2.market, borrower, secondFill);

        take(firstFill, lender, borrowerOffer);

        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        take(secondFill + 1, lender, borrowerOffer2);

        take(secondFill, lender, borrowerOffer2);
    }

    function testSellGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.maxUnits = firstFill + secondFill;
        lenderOffer.tick = MAX_TICK;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.market.maturity = market.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(market, borrower, firstFill);
        collateralize(lenderOffer2.market, borrower, secondFill);

        take(firstFill, borrower, lenderOffer);

        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        take(secondFill + 1, borrower, lenderOffer2);

        take(secondFill, borrower, lenderOffer2);
    }

    // other tests.

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatch(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, MAX_TICK / 4, MAX_TICK);
        tick2 = bound(tick2, MAX_TICK / 4, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price1 > price2);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = tick1;
        lenderOffer.maxUnits = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivUp(price1, WAD));
        collateralize(market, borrower, units);

        take(units, address(this), borrowerOffer);
        take(units, address(this), lenderOffer);

        assertEq(midnight.creditOf(id, address(this)), 0, "credit");
        assertEq(midnight.debtOf(id, address(this)), 0, "debt");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, MAX_TICK / 4, MAX_TICK);
        tick2 = bound(tick2, MAX_TICK / 4, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price2 > price1);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = tick1;
        lenderOffer.maxUnits = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), 1); // cover up to 1-wei rounding gap from mulDivUp on sell offer
        collateralize(market, borrower, units);
        collateralize(market, address(this), units);

        take(units, address(this), lenderOffer);
        take(units, address(this), borrowerOffer);

        assertEq(midnight.creditOf(id, address(this)), 0, "credit");
        assertEq(midnight.debtOf(id, address(this)), 0, "debt");
    }

    function testBuyPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, market.maturity + 1, type(uint32).max);
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.maxUnits = 100;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(market, borrower, 100);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(100, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, market.maturity + 1, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.maxUnits = 100;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(market, borrower, 100);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(100, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(market, borrower, collateralized);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        lenderOffer.maxUnits = units;
        lenderOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, collateralized);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        take(units, borrower, lenderOffer);
    }

    function testTakeOfferNotStarted(uint256 start) public {
        start = bound(start, block.timestamp + 1, type(uint256).max);
        Offer memory badOffer = lenderOffer;
        badOffer.start = start;
        vm.expectRevert(IMidnight.OfferNotStarted.selector);
        take(0, borrower, badOffer);
    }

    function testTakeOfferExpired(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, type(uint64).max);
        vm.warp(lenderOffer.expiry + elapsed);
        vm.expectRevert(IMidnight.OfferExpired.selector);
        take(0, borrower, lenderOffer);
    }

    function testTakeBuyerAndSellerSame(uint256 pkey) public {
        pkey = bound(pkey, 1, type(uint128).max);
        address taker = vm.addr(pkey);
        privateKey[taker] = pkey;
        lenderOffer.maker = taker;

        vm.expectRevert(IMidnight.SelfTake.selector);
        take(0, taker, lenderOffer);
    }

    // maxAssets tests. maxAssets caps buyerAssets for buy offers and sellerAssets for sell offers.

    function testMaxAssetsSellerRevert() public {
        uint256 units = 100e18;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        borrowerOffer.maxUnits = 0;
        borrowerOffer.maxAssets = 1;

        vm.expectRevert(IMidnight.ConsumedAssets.selector);
        take(units, lender, borrowerOffer);
    }

    function testMaxAssetsSellerPass(uint256 units) public {
        units = bound(units, 1, maxAssets);
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        borrowerOffer.maxUnits = 0;
        borrowerOffer.maxAssets = type(uint128).max;

        (, uint256 sellerAssets) = take(units, lender, borrowerOffer);

        assertTrue(sellerAssets > 0);
    }

    function testMaxAssetsBuyerRevert() public {
        uint256 units = 100e18;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        lenderOffer.maxUnits = 0;
        lenderOffer.maxAssets = 1;

        vm.expectRevert(IMidnight.ConsumedAssets.selector);
        take(units, borrower, lenderOffer);
    }

    function testMaxAssetsBuyerPass(uint256 units) public {
        units = bound(units, 1, maxAssets);
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        lenderOffer.maxUnits = 0;
        lenderOffer.maxAssets = type(uint128).max;

        (uint256 buyerAssets,) = take(units, borrower, lenderOffer);

        assertTrue(buyerAssets > 0);
    }

    function testMaxAssetsSellerExact() public {
        uint256 units = 100e18;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 expectedSellerAssets = units.mulDivUp(price, WAD);

        borrowerOffer.maxUnits = 0;
        borrowerOffer.maxAssets = expectedSellerAssets;

        (, uint256 sellerAssets) = take(units, lender, borrowerOffer);
        assertEq(sellerAssets, expectedSellerAssets);
    }

    function testMaxAssetsBuyerExact() public {
        uint256 units = 100e18;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 expectedBuyerAssets = units.mulDivDown(price, WAD);

        lenderOffer.maxUnits = 0;
        lenderOffer.maxAssets = expectedBuyerAssets;

        (uint256 buyerAssets,) = take(units, borrower, lenderOffer);
        assertEq(buyerAssets, expectedBuyerAssets);
    }

    function testMaxAssetsZeroMeansNoLimitForSeller(uint256 units) public {
        units = bound(units, 1, maxAssets);
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        borrowerOffer.maxAssets = 0;

        take(units, lender, borrowerOffer);
    }

    function testMaxAssetsZeroMeansNoLimitForBuyer(uint256 units) public {
        units = bound(units, 1, maxAssets);
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        lenderOffer.maxAssets = 0;

        take(units, borrower, lenderOffer);
    }

    function testMultipleMaxRevert() public {
        uint256 units = 100e18;
        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        lenderOffer.maxAssets = 1e18;
        lenderOffer.maxUnits = 1e18;

        vm.expectRevert(IMidnight.MultipleNonZero.selector);
        take(units, borrower, lenderOffer);
    }

    // Show that a buy offer with offerPrice < WAD can be taken with units > 0
    function testBugBuyMaxAssetsBypass() public {
        deal(address(loanToken), lender, 0); // lender pays 0
        collateralize(market, borrower, 100);

        lenderOffer.maxUnits = 0;
        lenderOffer.maxAssets = 1;
        lenderOffer.tick = MAX_TICK - 16; // offerPrice < WAD

        // Fully consume the offer before the take.
        vm.prank(lender);
        midnight.setConsumed(lenderOffer.group, lenderOffer.maxAssets, lender);

        uint256 lenderCreditBefore = midnight.creditOf(id, lender);
        uint256 borrowerDebtBefore = midnight.debtOf(id, borrower);
        uint256 totalUnitsBefore = midnight.totalUnits(id);
        uint256 lenderBalBefore = loanToken.balanceOf(lender);
        uint256 borrowerBalBefore = loanToken.balanceOf(borrower);

        (uint256 buyerAssets, uint256 sellerAssets) = take(1, borrower, lenderOffer);

        assertEq(buyerAssets, 0);
        assertEq(sellerAssets, 0);

        // Nothing observable to the cap or token balances changed:
        assertEq(midnight.consumed(lender, lenderOffer.group), lenderOffer.maxAssets);
        assertEq(loanToken.balanceOf(lender), lenderBalBefore);
        assertEq(loanToken.balanceOf(borrower), borrowerBalBefore);
        // But position state strictly changed:
        assertGt(midnight.creditOf(id, lender), lenderCreditBefore);
        assertGt(midnight.debtOf(id, borrower), borrowerDebtBefore);
        assertGt(midnight.totalUnits(id), totalUnitsBefore);
    }

    // test tree / signatures.

    function testTakeInvalidRoot(bytes32 invalidRoot) public {
        vm.assume(invalidRoot != root([lenderOffer]));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, invalidRoot, 0, new bytes32[](0))
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        Signature memory _sig = Signature({v: 1, r: 0, s: 0});
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            abi.encode(_sig, root([lenderOffer]), 0, new bytes32[](0))
        );
    }

    function testTakeByRatificationSameAsMaker(uint256 otherPrivateKey, address sender) public {
        vm.assume(sender != address(0));
        otherPrivateKey = boundPrivateKey(otherPrivateKey);
        IsRatifiedCallback ratifier = new IsRatifiedCallback();
        lenderOffer.maker = address(ratifier);
        lenderOffer.ratifier = address(ratifier);

        privateKey[vm.addr(otherPrivateKey)] = otherPrivateKey;

        vm.prank(address(ratifier));

        midnight.setIsAuthorized(address(ratifier), address(ratifier), true);
        bytes memory _ratifierData = merkleRatifierData([lenderOffer], vm.addr(otherPrivateKey));
        vm.expectCall(address(ratifier), abi.encodeCall(IRatifier.isRatified, (lenderOffer, _ratifierData)));
        vm.prank(sender);
        midnight.take(0, sender, address(0), hex"", sender, lenderOffer, _ratifierData);
    }

    function testTakeByRatificationDifferentFromMaker(address maker, address sender, uint256 otherPrivateKey) public {
        otherPrivateKey = boundPrivateKey(otherPrivateKey);
        vm.assume(sender != address(0));
        vm.assume(maker != sender);
        vm.assume(maker != address(0));
        IsRatifiedCallback ratifier = new IsRatifiedCallback();
        vm.assume(maker != address(ratifier));
        lenderOffer.maker = maker;
        lenderOffer.ratifier = address(ratifier);

        privateKey[vm.addr(otherPrivateKey)] = otherPrivateKey;

        vm.prank(maker);
        midnight.setIsAuthorized(maker, address(ratifier), true);
        bytes memory _ratifierData = merkleRatifierData([lenderOffer], vm.addr(otherPrivateKey));
        vm.expectCall(address(ratifier), abi.encodeCall(IRatifier.isRatified, (lenderOffer, _ratifierData)));
        vm.prank(sender);
        midnight.take(0, sender, address(0), hex"", sender, lenderOffer, _ratifierData);
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1 && _proof.length <= 20);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer]), 0, _proof)
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafHash(Offer memory otherOffer, bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1 && _proof.length <= 20);
        vm.assume(_proof[0] != HashLib.hashOffer(otherOffer));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 0, _proof)
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafIndex(Offer memory otherOffer) public {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = HashLib.hashOffer(otherOffer);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 1, _proof)
        );
    }

    function testTakeTwoLeaves(uint256 units, Offer memory otherOffer) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = units;

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 0, proof([lenderOffer, otherOffer]))
        );
    }

    // Adding salt to the expiry to test different leaf hashes.
    function testTakeFourLeaves(uint256 units, uint256 saltTimestamp1, uint256 saltTimestamp2, uint256 saltTimestamp3)
        public
    {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = units;

        Offer memory offer0 = lenderOffer;

        Offer memory offer1 = lenderOffer;
        offer1.expiry += bound(saltTimestamp1, 0, type(uint32).max);

        Offer memory offer2 = lenderOffer;
        offer2.expiry += bound(saltTimestamp2, 0, type(uint32).max);

        Offer memory offer3 = lenderOffer;
        offer3.expiry += bound(saltTimestamp3, 0, type(uint32).max);

        uint256 snapshot = vm.snapshotState();
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer0,
            merkleRatifierData(
                offer0, root([offer0, offer1, offer2, offer3]), 0, proofFirstLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer1,
            merkleRatifierData(
                offer1, root([offer0, offer1, offer2, offer3]), 1, proofSecondLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer2,
            merkleRatifierData(
                offer2, root([offer0, offer1, offer2, offer3]), 2, proofThirdLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer3,
            merkleRatifierData(
                offer3, root([offer0, offer1, offer2, offer3]), 3, proofFourthLeaf([offer0, offer1, offer2, offer3])
            )
        );
    }

    function testTakeNotRatified() public {
        vm.expectRevert();
        vm.prank(borrower);
        midnight.take(100, borrower, address(0), hex"", borrower, lenderOffer, emptySig);
    }

    function testTakeOfferValidSignature(uint256 makerSecretKey, address sender) public {
        vm.assume(sender != address(0));
        makerSecretKey = boundPrivateKey(makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.assume(sender != vm.addr(makerSecretKey));
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);
        vm.prank(sender);
        midnight.take(0, sender, address(0), hex"", sender, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    function testTakeOfferRatified(address maker, address sender) public {
        vm.assume(sender != address(0));
        vm.assume(maker != sender);
        vm.assume(maker != address(0));
        IsRatifiedCallback ratifier = new IsRatifiedCallback();
        lenderOffer.maker = maker;
        lenderOffer.ratifier = address(ratifier);
        vm.prank(maker);
        midnight.setIsAuthorized(maker, address(ratifier), true);
        vm.prank(sender);
        midnight.take(0, sender, address(0), hex"", sender, lenderOffer, emptySig);
    }

    function testOfferAuthorization(uint256 makerSecretKey, address sender, uint256 otherSecretKey) public {
        makerSecretKey = boundPrivateKey(makerSecretKey);
        otherSecretKey = boundPrivateKey(otherSecretKey);
        vm.assume(otherSecretKey != makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        privateKey[vm.addr(otherSecretKey)] = otherSecretKey;

        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        vm.prank(sender);
        midnight.take(
            100,
            sender,
            address(0),
            hex"",
            sender,
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey))
        );
    }

    function testOfferAuthorizationAuthorizedSigner(uint256 makerSecretKey, address sender, uint256 otherSecretKey)
        public
    {
        vm.assume(sender != address(0));
        makerSecretKey = boundPrivateKey(makerSecretKey);
        otherSecretKey = boundPrivateKey(otherSecretKey);
        vm.assume(otherSecretKey != makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        privateKey[vm.addr(otherSecretKey)] = otherSecretKey;

        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.assume(sender != lenderOffer.maker);

        vm.prank(vm.addr(makerSecretKey));

        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);
        vm.prank(lenderOffer.maker);
        midnight.setIsAuthorized(lenderOffer.maker, vm.addr(otherSecretKey), true);
        vm.prank(sender);
        midnight.take(
            0,
            sender,
            address(0),
            hex"",
            sender,
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey))
        );
    }

    function testTakeRatificationFailed(address maker, address sender, uint256 signerPrivateKey) public {
        vm.assume(maker != sender);
        vm.assume(maker != address(0));
        signerPrivateKey = boundPrivateKey(signerPrivateKey);
        privateKey[vm.addr(signerPrivateKey)] = signerPrivateKey;
        IsRatifiedCallback ratifier = new IsRatifiedCallback();
        ratifier.setReturnValue(bytes32(0));
        lenderOffer.maker = maker;
        lenderOffer.ratifier = address(ratifier);

        vm.prank(maker);
        midnight.setIsAuthorized(maker, address(ratifier), true);
        vm.expectRevert(IMidnight.RatifierFail.selector);
        vm.prank(sender);
        midnight.take(
            0,
            sender,
            address(0),
            hex"",
            sender,
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(signerPrivateKey))
        );
    }

    function testOrderNotAuthorized(address taker, address sender) public {
        vm.assume(sender != address(this));
        vm.assume(taker != sender);
        vm.assume(!midnight.isAuthorized(taker, sender));

        vm.expectRevert(IMidnight.TakerUnauthorized.selector);
        vm.prank(sender);
        midnight.take(100, taker, address(0), hex"", taker, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    function testOrderByTaker(address taker) public {
        vm.assume(taker != address(0));
        vm.assume(taker != lenderOffer.maker);
        vm.prank(taker);
        midnight.take(0, taker, address(0), hex"", taker, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    function testOrderByAuthorized(address taker, address sender) public {
        vm.assume(taker != address(0));
        vm.assume(sender != address(0));
        vm.assume(taker != sender);
        vm.assume(taker != lenderOffer.maker);
        vm.prank(taker);
        midnight.setIsAuthorized(taker, sender, true);
        vm.prank(sender);
        midnight.take(0, taker, address(0), hex"", taker, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    // test callbacks.

    function addCredit(address user, uint256 units) internal {
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        Offer memory offer = borrowerOffer;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.group = keccak256("otherBorrower");
        collateralize(market, otherBorrower, units);
        deal(address(loanToken), user, units.mulDivUp(price, WAD));
        take(units, user, offer);
    }

    function testBuySellerCallback(uint256 units, uint32 continuousFee) public {
        units = bound(units, 0, maxAssets);
        continuousFee = uint32(bound(continuousFee, 0, MAX_CONTINUOUS_FEE));
        midnight.setMarketContinuousFee(id, continuousFee);
        addCredit(borrower, units);

        uint256 collateral = units.mulDivUp(WAD, market.collateralParams[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(0, collateral);
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        deal(market.collateralParams[0].token, borrowerOffer.callback, collateral);
        assertEq(midnight.collateral(id, borrower, 0), 0);

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, borrowerOffer.callback, true);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateral(id, borrower, 0), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
        assertEq(
            BorrowCallback(borrowerOffer.callback).recordedPendingFeeDecrease(),
            units.mulDivDown(continuousFee * (market.maturity - block.timestamp), WAD),
            "pendingFeeDecrease"
        );
    }

    function testSellSellerCallback(uint256 units, uint32 continuousFee) public {
        units = bound(units, 0, maxAssets);
        continuousFee = uint32(bound(continuousFee, 0, MAX_CONTINUOUS_FEE));
        midnight.setMarketContinuousFee(id, continuousFee);
        uint256 collateral = units.mulDivUp(WAD, market.collateralParams[0].lltv);
        addCredit(borrower, units);

        lenderOffer.maxUnits = units;
        lenderOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        deal(market.collateralParams[0].token, callback, collateral);

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, callback, true);

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            callback,
            abi.encode(0, collateral),
            borrower,
            lenderOffer,
            merkleRatifierData([lenderOffer])
        );
        assertEq(midnight.collateral(id, borrower, 0), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(0, collateral));
        assertEq(
            BorrowCallback(callback).recordedPendingFeeDecrease(),
            units.mulDivDown(continuousFee * (market.maturity - block.timestamp), WAD),
            "pendingFeeDecrease"
        );
    }

    function testSellSellerCallbackLiquidateRevertsWhileLiquidationLocked() public {
        uint256 units = 100e18;
        uint256 repaidUnits = 1e18;
        uint256 collateral = units.mulDivUp(WAD, market.collateralParams[0].lltv);
        lenderOffer.maxUnits = units;
        lenderOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        ReentrantLiquidateBorrowCallback callback = new ReentrantLiquidateBorrowCallback();
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        deal(market.collateralParams[0].token, address(callback), collateral);
        deal(address(loanToken), address(callback), repaidUnits);

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(callback), true);

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(callback),
            abi.encode(0, collateral, repaidUnits),
            borrower,
            lenderOffer,
            merkleRatifierData([lenderOffer])
        );

        assertFalse(callback.liquidateSucceeded());
        assertEq(callback.liquidateErrorSelector(), IMidnight.NotLiquidatable.selector);
        assertEq(midnight.debtOf(id, borrower), units);
        assertEq(midnight.collateral(id, borrower, 0), collateral);
    }

    // Show the effect of the wasLocked variable in take.
    // The variable is not necessary but makes the behavior easy to describe.
    // With wasLocked, a nested take does not restore liquidatability.
    function testSellNestedTakeLiquidateRevertsWhileLiquidationLocked() public {
        uint256 units = 100e18;
        uint256 repaidUnits = 1e18;
        uint256 collateral = units.mulDivUp(WAD, market.collateralParams[0].lltv);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        lenderOffer.maxUnits = 2 * units;
        lenderOffer.tick = MAX_TICK;

        NestedTakeReentrantLiquidateCallback callback = new NestedTakeReentrantLiquidateCallback();
        deal(address(loanToken), lender, (2 * units).mulDivDown(price, WAD));
        deal(market.collateralParams[0].token, address(callback), 2 * collateral);
        deal(address(loanToken), address(callback), repaidUnits);

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(callback), true);

        callback.prepare(lenderOffer, merkleRatifierData([lenderOffer]), units, 0, 2 * collateral, repaidUnits);

        vm.prank(borrower);
        midnight.take(units, borrower, address(callback), "", borrower, lenderOffer, merkleRatifierData([lenderOffer]));

        assertTrue(callback.reentered());
        assertFalse(callback.liquidateSucceeded());
        assertEq(callback.liquidateErrorSelector(), IMidnight.NotLiquidatable.selector);
        assertTrue(midnight.liquidationLocked(id, borrower) == false);
        assertEq(midnight.debtOf(id, borrower), 2 * units);
        assertEq(midnight.collateral(id, borrower, 0), 2 * collateral);
    }

    function testSellSellerCallbackRevertsOnInvalidReturn(uint256 units) public {
        units = bound(units, 1, maxAssets);
        lenderOffer.maxUnits = units;
        lenderOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        address callback = address(new InvalidSellCallback());

        vm.expectRevert(IMidnight.WrongSellCallbackReturnValue.selector);
        vm.prank(borrower);
        midnight.take(units, borrower, callback, hex"", borrower, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    function testSellBuyerCallback(uint256 units, uint32 continuousFee) public {
        units = bound(units, 0, maxAssets);
        continuousFee = uint32(bound(continuousFee, 0, MAX_CONTINUOUS_FEE));
        midnight.setMarketContinuousFee(id, continuousFee);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivDown(price, WAD);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.maxUnits = units;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(market, borrower, units);

        take(units, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
        assertEq(
            LendCallback(lenderOffer.callback).recordedPendingFeeIncrease(),
            units.mulDivDown(continuousFee * (market.maturity - block.timestamp), WAD),
            "pendingFeeIncrease"
        );
    }

    function testBuyBuyerCallback(uint256 units, uint32 continuousFee) public {
        units = bound(units, 0, maxAssets);
        continuousFee = uint32(bound(continuousFee, 0, MAX_CONTINUOUS_FEE));
        midnight.setMarketContinuousFee(id, continuousFee);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        (address _otherLender,) = makeAddrAndKey("otherLender");
        address callback = address(new LendCallback());
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), callback, assets);
        collateralize(market, borrower, units);

        vm.prank(_otherLender);
        midnight.take(
            units,
            _otherLender,
            callback,
            abi.encode(address(loanToken), assets),
            address(0),
            borrowerOffer,
            merkleRatifierData([borrowerOffer])
        );
        assertEq(LendCallback(callback).recordedData(), abi.encode(address(loanToken), assets));
        assertEq(
            LendCallback(callback).recordedPendingFeeIncrease(),
            units.mulDivDown(continuousFee * (market.maturity - block.timestamp), WAD),
            "pendingFeeIncrease"
        );
    }

    // Summary of zero price tests:
    //
    // Trading at 0 succeeds in those cases:
    // - any offer / unit take input / 0 trading fee.
    // - sell offer / unit take input / > 0 trading fee.
    //
    // Otherwise it fails:
    // - by underflow when the trading fee is > 0, and the offer is a buy offer.

    // fee=0, sell, units
    function testPriceZeroNoTradingFeeSell() public {
        uint256 units = 1e18;
        borrowerOffer.tick = 0;
        borrowerOffer.maxUnits = units;
        collateralize(market, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets) = take(units, lender, borrowerOffer);
        assertEq(buyerAssets, 0, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.creditOf(id, lender), units, "creditOf");
        assertEq(midnight.debtOf(id, borrower), units, "debtOf");
    }

    // fee>0, buy, units
    function testPriceZeroWithTradingFeeBuy() public {
        midnight.touchMarket(market);
        midnight.setMarketTradingFee(id, 1, 1e12);
        uint256 units = 1e18;
        lenderOffer.tick = 0;
        lenderOffer.maxUnits = units;
        collateralize(market, borrower, units);
        vm.expectRevert();
        take(units, borrower, lenderOffer);
    }

    // fee>0, sell, units
    function testPriceZeroWithTradingFeeSell() public {
        midnight.touchMarket(market);
        midnight.setMarketTradingFee(id, 1, 1e12);
        uint256 fee = midnight.tradingFee(id, market.maturity - block.timestamp);
        uint256 units = 1e18;
        borrowerOffer.tick = 0;
        borrowerOffer.maxUnits = units;
        uint256 expectedBuyerAssets = units.mulDivUp(fee, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(market, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets) = take(units, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.creditOf(id, lender), units, "creditOf");
        assertEq(midnight.debtOf(id, borrower), units, "debtOf");
    }

    function testTradeWithAddressZero(uint256 units) public {
        units = bound(units, 1, maxAssets);

        // address(0) as maker cannot authorize the ratifier
        Offer memory zeroOffer;
        zeroOffer.buy = true;
        zeroOffer.maker = address(0);
        zeroOffer.ratifier = address(ecrecoverRatifier);
        zeroOffer.maxUnits = units;
        zeroOffer.market = market;
        zeroOffer.expiry = block.timestamp + 200;
        zeroOffer.tick = 0; // 0 price so any units transfer 0 assets

        // taker = borrower, needs collateral
        collateralize(market, borrower, units);

        Signature memory badSig;

        vm.expectRevert(IMidnight.RatifierUnauthorized.selector);
        vm.prank(borrower);
        midnight.take(units, borrower, address(0), hex"", borrower, zeroOffer, abi.encode(badSig));
    }

    function testBuyBuyerCallbackRevertsOnInvalidReturn(uint256 units) public {
        units = bound(units, 1, maxAssets);
        borrowerOffer.maxUnits = units;
        borrowerOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        address callback = address(new InvalidBuyCallback());
        deal(address(loanToken), callback, assets);
        collateralize(market, borrower, units);

        vm.expectRevert(IMidnight.WrongBuyCallbackReturnValue.selector);
        vm.prank(lender);
        midnight.take(units, lender, callback, hex"", address(0), borrowerOffer, merkleRatifierData([borrowerOffer]));
    }
}

contract InvalidBuyCallback is IBuyCallback {
    function onBuy(bytes32, Market memory, address, uint256, uint256, uint256, bytes memory)
        external
        pure
        returns (bytes32)
    {
        return bytes32(0);
    }
}

contract BorrowCallback is ISellCallback {
    bytes public recordedData;
    bytes32 public recordedId;
    uint256 public recordedPendingFeeDecrease;

    function onSell(
        bytes32 id,
        Market memory market,
        address seller,
        address,
        uint256,
        uint256,
        uint256 pendingFeeDecrease,
        bytes memory data
    ) external returns (bytes32) {
        require(id == IdLib.toId(market, block.chainid, msg.sender), "wrong id");
        recordedId = id;
        recordedData = data;
        recordedPendingFeeDecrease = pendingFeeDecrease;
        (uint256 collateralIndex, uint256 amount) = abi.decode(data, (uint256, uint256));
        address collateralToken = market.collateralParams[collateralIndex].token;
        ERC20(collateralToken).approve(msg.sender, amount);
        Midnight(msg.sender).supplyCollateral(market, collateralIndex, amount, seller);
        return CALLBACK_SUCCESS;
    }
}

contract ReentrantLiquidateBorrowCallback is ISellCallback {
    bool public liquidateSucceeded;
    bytes4 public liquidateErrorSelector;

    function onSell(
        bytes32 id,
        Market memory market,
        address seller,
        address,
        uint256,
        uint256,
        uint256,
        bytes memory data
    ) external returns (bytes32) {
        require(id == IdLib.toId(market, block.chainid, msg.sender), "wrong id");
        (uint256 collateralIndex, uint256 collateralAmount, uint256 repaidUnits) =
            abi.decode(data, (uint256, uint256, uint256));
        address collateralToken = market.collateralParams[collateralIndex].token;
        ERC20(collateralToken).approve(msg.sender, collateralAmount);
        Midnight(msg.sender).supplyCollateral(market, collateralIndex, collateralAmount, seller);

        Oracle oracle = Oracle(market.collateralParams[collateralIndex].oracle);
        uint256 healthyPrice = oracle.price();
        oracle.setPrice(healthyPrice / 2);
        ERC20(market.loanToken).approve(msg.sender, repaidUnits);
        try Midnight(msg.sender)
            .liquidate(market, collateralIndex, 0, repaidUnits, seller, address(this), address(0), "") returns (
            uint256, uint256
        ) {
            liquidateSucceeded = true;
        } catch (bytes memory revertData) {
            // forge-lint: disable-next-line(unsafe-typecast)
            liquidateErrorSelector = bytes4(revertData);
        }
        oracle.setPrice(healthyPrice);
        return CALLBACK_SUCCESS;
    }
}

contract NestedTakeReentrantLiquidateCallback is ISellCallback {
    bool public reentered;
    bool public liquidateSucceeded;
    bytes4 public liquidateErrorSelector;

    Offer internal storedOffer;
    bytes internal storedSig;
    uint256 internal innerUnits;
    uint256 internal storedCollateralIndex;
    uint256 internal storedCollateralAmount;
    uint256 internal storedRepaidUnits;

    function prepare(
        Offer memory _offer,
        bytes memory _sig,
        uint256 _innerUnits,
        uint256 _collateralIndex,
        uint256 _collateralAmount,
        uint256 _repaidUnits
    ) external {
        storedOffer = _offer;
        storedSig = _sig;
        innerUnits = _innerUnits;
        storedCollateralIndex = _collateralIndex;
        storedCollateralAmount = _collateralAmount;
        storedRepaidUnits = _repaidUnits;
    }

    function onSell(bytes32 id, Market memory market, address seller, address, uint256, uint256, uint256, bytes memory)
        external
        returns (bytes32)
    {
        require(id == IdLib.toId(market, block.chainid, msg.sender), "wrong id");
        if (!reentered) {
            uint256 idx = storedCollateralIndex;
            address collateralToken = market.collateralParams[idx].token;
            ERC20(collateralToken).approve(msg.sender, storedCollateralAmount);
            Midnight(msg.sender).supplyCollateral(market, idx, storedCollateralAmount, seller);

            reentered = true;
            Offer memory nestedOffer = storedOffer;
            Midnight(msg.sender).take(innerUnits, seller, address(this), "", seller, nestedOffer, storedSig);

            Oracle oracle = Oracle(market.collateralParams[idx].oracle);
            uint256 healthyPrice = oracle.price();
            oracle.setPrice(healthyPrice / 2);
            ERC20(market.loanToken).approve(msg.sender, storedRepaidUnits);
            try Midnight(msg.sender)
                .liquidate(market, idx, 0, storedRepaidUnits, seller, address(this), address(0), "") returns (
                uint256, uint256
            ) {
                liquidateSucceeded = true;
            } catch (bytes memory revertData) {
                // forge-lint: disable-next-line(unsafe-typecast)
                liquidateErrorSelector = bytes4(revertData);
            }
            oracle.setPrice(healthyPrice);
        }
        return CALLBACK_SUCCESS;
    }
}

contract LendCallback is IBuyCallback {
    bytes public recordedData;

    bytes32 public recordedId;
    uint256 public recordedPendingFeeIncrease;

    function onBuy(
        bytes32 id,
        Market memory market,
        address,
        uint256 buyerAssets,
        uint256,
        uint256 pendingFeeIncrease,
        bytes memory data
    ) external returns (bytes32) {
        require(id == IdLib.toId(market, block.chainid, msg.sender), "wrong id");
        recordedId = id;
        recordedData = data;
        recordedPendingFeeIncrease = pendingFeeIncrease;
        ERC20(market.loanToken).approve(msg.sender, buyerAssets);
        return CALLBACK_SUCCESS;
    }
}

contract InvalidSellCallback is ISellCallback {
    function onSell(bytes32, Market memory, address, address, uint256, uint256, uint256, bytes memory)
        external
        pure
        returns (bytes32)
    {
        return bytes32(0);
    }
}

contract IsRatifiedCallback is IRatifier {
    bytes32 public returnValue = CALLBACK_SUCCESS;

    function isRatified(Offer memory, bytes memory) external view returns (bytes32) {
        return returnValue;
    }

    function setReturnValue(bytes32 _returnValue) external {
        returnValue = _returnValue;
    }
}
