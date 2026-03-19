// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";

contract TakeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    Offer internal otherLenderOffer;
    Offer internal otherBorrowerOffer;

    uint256 internal maxAssets = 1e33; // to refine.

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
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
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationUnits = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.obligationUnits = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = MAX_TICK;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.obligationUnits = type(uint256).max;
        otherBorrowerOffer.obligation = obligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;
    }

    // tests.

    // path 1: Lender enters + borrower enters.

    function testBuy1(uint256 obligationUnits, uint256 tick) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedAssets = obligationUnits.mulDivUp(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);

        take(obligationUnits, lender, borrowerOffer);

        assertEq(midnight.creditOf(id, lender), obligationUnits, "lender units");
        assertEq(midnight.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(midnight.totalUnits(id), obligationUnits, "total units");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(borrower, borrowerOffer.group), obligationUnits, "consumed");
    }

    function testSell1(uint256 obligationUnits, uint256 tick) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedAssets = obligationUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);

        take(obligationUnits, borrower, lenderOffer);

        assertEq(midnight.creditOf(id, lender), obligationUnits, "lender units");
        assertEq(midnight.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(midnight.totalUnits(id), obligationUnits, "total units");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(lender, lenderOffer.group), obligationUnits, "consumed");
    }

    // path 2: Lender enters + lender exits.

    function testBuy2(uint256 obligationUnits, uint256 tick, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 actualOtherLenderCredit = midnight.creditOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        otherLenderOffer.buy = false;
        otherLenderOffer.obligationUnits = type(uint256).max;
        otherLenderOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, lender, otherLenderOffer);

        assertEq(midnight.creditOf(id, lender), obligationUnits, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), actualOtherLenderCredit - obligationUnits, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testSell2(uint256 obligationUnits, uint256 tick, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 actualOtherLenderCredit = midnight.creditOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        lenderOffer.obligationUnits = type(uint256).max;
        lenderOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, otherLender, lenderOffer);

        assertEq(midnight.creditOf(id, lender), obligationUnits, "lender units");
        assertEq(midnight.debtOf(id, lender), 0, "lender debt");
        assertEq(midnight.creditOf(id, otherLender), actualOtherLenderCredit - obligationUnits, "other lender units");
        assertEq(midnight.debtOf(id, otherLender), 0, "other lender debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    // Lender sells more than their balance, crossing to borrower.
    function testCrossTopDown(uint256 obligationUnits, uint256 otherLenderUnits) public {
        otherLenderUnits = bound(otherLenderUnits, 1, maxAssets - 1);
        obligationUnits = bound(obligationUnits, otherLenderUnits + 1, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, obligationUnits.mulDivUp(price, WAD));
        collateralize(obligation, otherLender, obligationUnits);
        otherLenderOffer.tick = MAX_TICK;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, lender, otherLenderOffer);

        // otherLender crossed from lender to borrower.
        assertEq(midnight.creditOf(id, otherLender), 0, "otherLender credit");
        assertEq(midnight.debtOf(id, otherLender), obligationUnits - otherLenderCredit, "otherLender debt");
        assertEq(midnight.creditOf(id, lender), obligationUnits, "lender credit");
        assertEq(midnight.totalUnits(id), totalUnitsBefore + obligationUnits - otherLenderCredit, "total units");
    }

    // path 3: Borrower exits + borrower enters.

    function testBuy3(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), otherBorrower, obligationUnits.mulDivUp(price, WAD));
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, otherBorrower, borrowerOffer);

        assertEq(midnight.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    function testSell3(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(obligation, borrower, obligationUnits);
        otherBorrowerOffer.obligationUnits = type(uint256).max;
        otherBorrowerOffer.tick = tick;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "total units");
    }

    // Borrower buys more than their debt, crossing to lender.
    function testCrossBottomUp(uint256 obligationUnits, uint256 otherUnits) public {
        otherUnits = bound(otherUnits, 1, maxAssets - 1);
        obligationUnits = bound(obligationUnits, otherUnits + 1, maxAssets);
        setupOtherUsers(obligation, otherUnits);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), otherBorrower, obligationUnits.mulDivUp(price, WAD));
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.tick = MAX_TICK;
        uint256 totalUnitsBefore = midnight.totalUnits(id);

        take(obligationUnits, otherBorrower, borrowerOffer);

        // otherBorrower crossed from borrower to lender.
        assertEq(midnight.debtOf(id, otherBorrower), 0, "otherBorrower debt");
        assertEq(midnight.creditOf(id, otherBorrower), obligationUnits - otherBorrowerDebt, "otherBorrower credit");
        assertEq(midnight.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(midnight.totalUnits(id), totalUnitsBefore + obligationUnits - otherBorrowerDebt, "total units");
    }

    // path 4: Borrower exits + lender exits.

    function testBuy4(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivUp(price, WAD);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherLenderOffer.obligationUnits = type(uint256).max;
        otherLenderOffer.tick = tick;
        deal(address(loanToken), otherBorrower, buyerAssets);

        take(obligationUnits, otherBorrower, otherLenderOffer);

        assertEq(midnight.creditOf(id, otherLender), otherLenderCredit - obligationUnits, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - obligationUnits, "total units");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
    }

    function testSell4(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderCredit = midnight.creditOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherBorrowerOffer.obligationUnits = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(obligationUnits, otherLender, otherBorrowerOffer);

        assertEq(midnight.creditOf(id, otherLender), otherLenderCredit - obligationUnits, "otherLender units");
        assertEq(midnight.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(midnight.totalUnits(id), otherBorrowerDebt - obligationUnits, "total units");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
    }

    // exitOnly tests.

    function testExitOnlyBuySuccess(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets);
        exitUnits = bound(exitUnits, 1, existingUnits);
        setupOtherUsers(obligation, existingUnits);

        otherBorrowerOffer.obligationUnits = exitUnits;
        otherBorrowerOffer.exitOnly = true;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), otherBorrower, exitUnits.mulDivUp(price, WAD));
        collateralize(obligation, borrower, exitUnits);

        uint256 debtBefore = midnight.debtOf(id, otherBorrower);

        take(exitUnits, borrower, otherBorrowerOffer);

        assertEq(midnight.creditOf(id, otherBorrower), 0, "no credit");
        assertEq(midnight.debtOf(id, otherBorrower), debtBefore - exitUnits, "debt reduced");
    }

    function testExitOnlyBuyRevert(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets - 1);
        exitUnits = bound(exitUnits, existingUnits + 1, maxAssets);
        setupOtherUsers(obligation, existingUnits);

        otherBorrowerOffer.obligationUnits = exitUnits;
        otherBorrowerOffer.exitOnly = true;

        vm.expectRevert("crossed");
        take(exitUnits, borrower, otherBorrowerOffer);
    }

    function testExitOnlySellSuccess(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets);
        exitUnits = bound(exitUnits, 1, existingUnits);
        setupOtherUsers(obligation, existingUnits);

        otherLenderOffer.obligationUnits = exitUnits;
        otherLenderOffer.exitOnly = true;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, exitUnits.mulDivUp(price, WAD));

        uint256 creditBefore = midnight.creditOf(id, otherLender);

        take(exitUnits, lender, otherLenderOffer);

        assertEq(midnight.debtOf(id, otherLender), 0, "no debt");
        assertEq(midnight.creditOf(id, otherLender), creditBefore - exitUnits, "credit reduced");
    }

    function testExitOnlySellRevert(uint256 existingUnits, uint256 exitUnits) public {
        existingUnits = bound(existingUnits, 1, maxAssets - 1);
        exitUnits = bound(exitUnits, existingUnits + 1, maxAssets);
        setupOtherUsers(obligation, existingUnits);

        otherLenderOffer.obligationUnits = exitUnits;
        otherLenderOffer.exitOnly = true;

        vm.expectRevert("crossed");
        take(exitUnits, lender, otherLenderOffer);
    }

    // group tests.

    function testBuyConsumed(
        uint256 obligationUnits,
        uint256 offerObligationUnits,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets - 1);
        offerObligationUnits = bound(offerObligationUnits, obligationUnits, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerObligationUnits - obligationUnits + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerObligationUnits - obligationUnits);
        borrowerOffer.obligationUnits = offerObligationUnits;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(obligationUnits, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, lender, borrowerOffer);

        take(secondPassingTake, lender, borrowerOffer);
    }

    function testSellConsumed(
        uint256 obligationUnits,
        uint256 offerObligationUnits,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets - 1);
        offerObligationUnits = bound(offerObligationUnits, obligationUnits, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerObligationUnits - obligationUnits + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerObligationUnits - obligationUnits);
        lenderOffer.obligationUnits = offerObligationUnits;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(obligationUnits, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, borrower, lenderOffer);

        take(secondPassingTake, borrower, lenderOffer);
    }

    function testBuyGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.obligationUnits = firstFill + secondFill;
        borrowerOffer.tick = MAX_TICK;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(firstFill, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, lender, borrowerOffer2);

        take(secondFill, lender, borrowerOffer2);
    }

    function testSellGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.obligationUnits = firstFill + secondFill;
        lenderOffer.tick = MAX_TICK;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(firstFill, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, borrower, lenderOffer2);

        take(secondFill, borrower, lenderOffer2);
    }

    // other tests.

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatch(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, 600, MAX_TICK);
        tick2 = bound(tick2, 600, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price1 > price2);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.obligationUnits = units;
        borrowerOffer.tick = tick1;
        lenderOffer.obligationUnits = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivUp(price1, WAD));
        collateralize(obligation, borrower, units);

        take(units, address(this), borrowerOffer);
        take(units, address(this), lenderOffer);

        assertEq(midnight.creditOf(id, address(this)), 0, "credit");
        assertEq(midnight.debtOf(id, address(this)), 0, "debt");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, 600, MAX_TICK);
        tick2 = bound(tick2, 600, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price2 > price1);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.obligationUnits = units;
        borrowerOffer.tick = tick1;
        lenderOffer.obligationUnits = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), 1); // cover up to 1-wei rounding gap from mulDivUp on sell offer
        collateralize(obligation, borrower, units);
        collateralize(obligation, address(this), units);

        take(units, address(this), lenderOffer);
        take(units, address(this), borrowerOffer);

        assertEq(midnight.creditOf(id, address(this)), 0, "credit");
        assertEq(midnight.debtOf(id, address(this)), 0, "debt");
    }

    function testBuyPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.obligationUnits = 100;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.obligationUnits = 100;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        borrowerOffer.obligationUnits = units;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("seller is unhealthy");
        take(units, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        lenderOffer.obligationUnits = units;
        lenderOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("seller is unhealthy");
        take(units, borrower, lenderOffer);
    }

    function testSession() public {
        vm.prank(lender);
        midnight.shuffleSession(lender);

        vm.expectRevert("invalid session");
        take(100, borrower, lenderOffer);
    }

    function testTakeOfferNotStarted(uint256 start) public {
        start = bound(start, block.timestamp + 1, type(uint256).max);
        Offer memory badOffer = lenderOffer;
        badOffer.start = start;
        vm.expectRevert("offer not started");
        take(0, borrower, badOffer);
    }

    function testTakeOfferExpired(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, type(uint64).max);
        vm.warp(lenderOffer.expiry + elapsed);
        vm.expectRevert("offer expired");
        take(0, borrower, lenderOffer);
    }

    function testTakeBuyerAndSellerSame(uint256 pkey) public {
        pkey = bound(pkey, 1, type(uint128).max);
        address taker = vm.addr(pkey);
        privateKey[taker] = pkey;
        lenderOffer.maker = taker;

        vm.expectRevert("buyer and seller cannot be the same");
        take(0, taker, lenderOffer);
    }

    // test tree / signatures.

    function testTakeWrongRoot() public {
        vm.expectRevert("invalid signature");
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([borrowerOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert("invalid signature");
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            Signature({v: 0, r: 0, s: 0}),
            root([lenderOffer]),
            proof([lenderOffer])
        );
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.expectRevert("invalid proof");
        vm.prank(borrower);
        midnight.take(
            100, borrower, address(0), hex"", borrower, lenderOffer, sig([lenderOffer]), root([lenderOffer]), proof
        );
    }

    function testTakeInvalidProofTwoLeaves(Offer memory otherOffer, bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.assume(proof[0] != keccak256(abi.encode(otherOffer)));
        vm.expectRevert("invalid proof");
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([lenderOffer, otherOffer]),
            root([lenderOffer, otherOffer]),
            proof
        );
    }

    function testTakeTwoLeaves(uint256 units, Offer memory otherOffer) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, units);
        lenderOffer.obligationUnits = units;

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([lenderOffer, otherOffer]),
            root([lenderOffer, otherOffer]),
            proof([lenderOffer, otherOffer])
        );
    }

    // test callbacks.

    function testBuySellerCallback(uint256 units) public {
        units = bound(units, 0, maxAssets);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(0, collateral);
        borrowerOffer.obligationUnits = units;
        borrowerOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(midnight.collateralOf(id, borrower, 0), 0);

        authorize(borrower, borrowerOffer.callback);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 units) public {
        units = bound(units, 0, maxAssets);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.obligationUnits = units;
        lenderOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        deal(obligation.collaterals[0].token, callback, collateral);

        authorize(borrower, callback);

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            callback,
            abi.encode(0, collateral),
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );
        assertEq(midnight.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(0, collateral));
    }

    function testSellBuyerCallback(uint256 units) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivDown(price, WAD);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.obligationUnits = units;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(obligation, borrower, units);

        take(units, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 units) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        (address _otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(_otherLender);
        loanToken.approve(address(midnight), assets);
        address callback = address(new LendCallback());
        borrowerOffer.obligationUnits = units;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), callback, assets);
        collateralize(obligation, borrower, units);

        vm.prank(_otherLender);
        midnight.take(
            units,
            _otherLender,
            callback,
            abi.encode(address(loanToken), assets),
            address(0),
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer])
        );
        assertEq(LendCallback(callback).recordedData(), abi.encode(address(loanToken), assets));
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
    function testPriceZero_NoTradingFee_sell() public {
        uint256 units = 1e18;
        borrowerOffer.tick = 0;
        borrowerOffer.obligationUnits = units;
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,) = take(units, lender, borrowerOffer);
        assertEq(buyerAssets, 0, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.creditOf(id, lender), units, "creditOf");
        assertEq(midnight.debtOf(id, borrower), units, "debtOf");
    }

    // fee>0, buy, units
    function testPriceZero_WithTradingFee_buy() public {
        midnight.touchObligation(obligation);
        midnight.setObligationTradingFee(id, 1, 1e12);
        uint256 units = 1e18;
        lenderOffer.tick = 0;
        lenderOffer.obligationUnits = units;
        collateralize(obligation, borrower, units);
        vm.expectRevert();
        take(units, borrower, lenderOffer);
    }

    // fee>0, sell, units
    function testPriceZero_WithTradingFee_sell() public {
        midnight.touchObligation(obligation);
        midnight.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        borrowerOffer.tick = 0;
        borrowerOffer.obligationUnits = units;
        uint256 expectedBuyerAssets = units.mulDivUp(fee, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,) = take(units, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.creditOf(id, lender), units, "creditOf");
        assertEq(midnight.debtOf(id, borrower), units, "debtOf");
    }
}

contract BorrowCallback is ICallbacks {
    bytes public recordedData;

    function onSell(Obligation memory obligation, address seller, uint256, uint256, uint256, bytes memory data)
        external
    {
        recordedData = data;
        (uint256 collateralIndex, uint256 amount) = abi.decode(data, (uint256, uint256));
        address collateralToken = obligation.collaterals[collateralIndex].token;
        ERC20(collateralToken).approve(msg.sender, amount);
        Midnight(msg.sender).supplyCollateral(obligation, collateralIndex, amount, seller);
    }

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        bytes memory data
    ) external {}

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}

contract LendCallback is ICallbacks {
    bytes public recordedData;

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        uint256,
        bytes memory data
    ) external {
        recordedData = data;
        require(ERC20(obligation.loanToken).transfer(buyer, buyerAssets), "transfer failed");
    }

    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        bytes memory data
    ) external {}

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
