// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
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

    // Bad debt creates a ~3.4x shares/units ratio, and price conversion can amplify by up to 100x (price > 0.01 ether).
    // Collateral = units / lltv adds another ~1.33x. Combined: 3.4 * 100 * 1.33 ≈ 400.
    uint256 internal maxAssets = type(uint128).max / 400;
    uint256 internal initialUnits;
    uint256 internal initialShares;

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
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = MAX_TICK;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.obligation = obligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = midnight.totalUnits(id);
        initialShares = midnight.totalShares(id);
    }

    // tests.

    // path 1: Lender enters + borrower enters.

    function testBuy1(uint256 obligationShares, uint256 tick) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedUnits = obligationShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivUp(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, expectedUnits);

        take(obligationShares, lender, borrowerOffer);

        assertEq(midnight.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(midnight.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(midnight.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(borrower, borrowerOffer.group), obligationShares, "consumed");
    }

    function testSell1(uint256 obligationShares, uint256 tick) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedUnits = obligationShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1).mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, expectedUnits);

        take(obligationShares, borrower, lenderOffer);

        assertEq(midnight.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(midnight.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(midnight.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(midnight.consumed(lender, lenderOffer.group), obligationShares, "consumed");
    }

    // path 2: Lender enters + lender exits.

    function testBuy2(uint256 obligationShares, uint256 tick, uint256 otherLenderShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivUp(price, WAD);
        otherLenderShares = bound(otherLenderShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, otherLenderShares);
        uint256 actualOtherLenderShares = midnight.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        otherLenderOffer.buy = false;
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.tick = tick;

        take(obligationShares, lender, otherLenderOffer);

        assertApproxEqAbs(midnight.sharesOf(id, lender), obligationShares, 1, "lender shares");
        assertApproxEqAbs(
            midnight.sharesOf(id, otherLender), actualOtherLenderShares - obligationShares, 1, "other lender shares"
        );
    }

    function testSell2(uint256 obligationShares, uint256 tick, uint256 otherLenderShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1).mulDivDown(price, WAD);
        otherLenderShares = bound(otherLenderShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, otherLenderShares);
        uint256 actualOtherLenderShares = midnight.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1);
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.tick = tick;

        take(obligationShares, otherLender, lenderOffer);

        assertApproxEqAbs(midnight.sharesOf(id, lender), obligationShares, 1, "lender shares");
        assertApproxEqAbs(
            midnight.sharesOf(id, otherLender), actualOtherLenderShares - obligationShares, 1, "other lender shares"
        );
    }

    function testCannotCrossTopDown(uint256 obligationShares, uint256 otherLenderShares) public {
        otherLenderShares = bound(otherLenderShares, 1, maxAssets - 1);
        obligationShares = bound(obligationShares, otherLenderShares + 1, maxAssets);
        setupOtherUsers(obligation, otherLenderShares);

        vm.expectRevert(stdError.arithmeticError);
        take(obligationShares, lender, otherLenderOffer);

        vm.expectRevert(stdError.arithmeticError);
        take(obligationShares, otherLender, lenderOffer);
    }

    // path 3: Borrower exits + borrower enters.

    function testBuy3(uint256 obligationShares, uint256 tick, uint256 existingShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        existingShares = bound(existingShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingShares);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(obligation, borrower, obligationShares);
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(
            address(loanToken),
            otherBorrower,
            obligationShares.mulDivUp(midnight.totalUnits(id) + 1, midnight.totalShares(id) + 1).mulDivUp(price, WAD)
        );

        take(obligationShares, otherBorrower, borrowerOffer);

        assertApproxEqAbs(midnight.debtOf(id, borrower), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            midnight.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
    }

    function testSell3(uint256 obligationShares, uint256 tick, uint256 existingShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        existingShares = bound(existingShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingShares);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);
        collateralize(obligation, borrower, obligationShares);
        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(obligationShares, borrower, otherBorrowerOffer);

        assertApproxEqAbs(midnight.debtOf(id, borrower), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            midnight.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
    }

    function testCannotCrossBottomUp(uint256 obligationShares, uint256 otherShares) public {
        // Lower bound ensures shares map to non-zero units after bad debt.
        otherShares = bound(otherShares, initialShares / initialUnits + 1, maxAssets - 1);
        obligationShares = bound(obligationShares, otherShares + 1, maxAssets);
        setupOtherUsers(obligation, otherShares);

        vm.expectRevert();
        take(obligationShares, borrower, otherBorrowerOffer);

        vm.expectRevert();
        take(obligationShares, otherBorrower, borrowerOffer);
    }

    // path 4: Borrower exits + lender exits.

    function testBuy4(uint256 obligationShares, uint256 tick, uint256 existingShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        existingShares = bound(existingShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingShares);
        uint256 expectedUnits = obligationShares.mulDivDown(midnight.totalUnits(id) + 1, midnight.totalShares(id) + 1);
        uint256 buyerAssets =
            obligationShares.mulDivUp(midnight.totalUnits(id) + 1, midnight.totalShares(id) + 1).mulDivUp(price, WAD);
        uint256 otherLenderSharesVal = midnight.sharesOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.tick = tick;
        deal(address(loanToken), otherBorrower, buyerAssets);

        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        take(obligationShares, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            midnight.sharesOf(id, otherLender), otherLenderSharesVal - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(
            midnight.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertApproxEqAbs(midnight.totalUnits(id), initialUnits + otherBorrowerDebt - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            midnight.totalShares(id), initialShares + otherLenderSharesVal - obligationShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender) - otherLenderBalanceBefore, buyerAssets, "otherLender balance");
    }

    function testSell4(uint256 obligationShares, uint256 tick, uint256 existingShares) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        existingShares = bound(existingShares, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingShares);
        uint256 otherLenderSharesVal = midnight.sharesOf(id, otherLender);
        uint256 otherBorrowerDebt = midnight.debtOf(id, otherBorrower);

        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        take(obligationShares, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            midnight.sharesOf(id, otherLender), otherLenderSharesVal - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(
            midnight.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertApproxEqAbs(midnight.totalUnits(id), initialUnits + otherBorrowerDebt - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            midnight.totalShares(id), initialShares + otherLenderSharesVal - obligationShares, 1, "total shares"
        );
        assertApproxEqAbs(
            loanToken.balanceOf(otherLender) - otherLenderBalanceBefore, buyerAssets, 1, "otherLender balance"
        );
    }

    // group tests.

    function testBuyConsumed(
        uint256 obligationShares,
        uint256 offerObligationShares,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        obligationShares = bound(obligationShares, 0, maxAssets - 1);
        offerObligationShares = bound(offerObligationShares, obligationShares, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerObligationShares - obligationShares + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerObligationShares - obligationShares);
        borrowerOffer.obligationShares = offerObligationShares;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(obligationShares, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, lender, borrowerOffer);

        take(secondPassingTake, lender, borrowerOffer);
    }

    function testSellConsumed(
        uint256 obligationShares,
        uint256 offerObligationShares,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        obligationShares = bound(obligationShares, 0, maxAssets - 1);
        offerObligationShares = bound(offerObligationShares, obligationShares, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerObligationShares - obligationShares + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerObligationShares - obligationShares);
        lenderOffer.obligationShares = offerObligationShares;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(obligationShares, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, borrower, lenderOffer);

        take(secondPassingTake, borrower, lenderOffer);
    }

    function testBuyGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.obligationShares = firstFill + secondFill;
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
        lenderOffer.obligationShares = firstFill + secondFill;
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
    function testMatch(uint256 shares, uint256 tick1, uint256 tick2) public {
        shares = bound(shares, 1, maxAssets);
        tick1 = bound(tick1, 600, MAX_TICK);
        tick2 = bound(tick2, 600, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price1 > price2);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        borrowerOffer.obligationShares = shares;
        borrowerOffer.tick = tick1;
        lenderOffer.obligationShares = shares;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivUp(price1, WAD));
        collateralize(obligation, borrower, units);

        take(shares, address(this), borrowerOffer);
        take(shares, address(this), lenderOffer);

        assertEq(midnight.sharesOf(id, address(this)), 0, "shares");
        assertEq(midnight.debtOf(id, address(this)), 0, "debt");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 shares, uint256 tick1, uint256 tick2) public {
        shares = bound(shares, 1, maxAssets);
        tick1 = bound(tick1, 600, MAX_TICK);
        tick2 = bound(tick2, 600, MAX_TICK);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price2 > price1);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        borrowerOffer.obligationShares = shares;
        borrowerOffer.tick = tick1;
        lenderOffer.obligationShares = shares;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivUp(price1, WAD));
        collateralize(obligation, borrower, units);
        collateralize(obligation, address(this), units);

        take(shares, address(this), lenderOffer);
        take(shares, address(this), borrowerOffer);

        assertEq(midnight.sharesOf(id, address(this)), 0, "shares");
        // debt may not be exactly 0 due to rounding in the two opposite directions
        assertApproxEqAbs(midnight.debtOf(id, address(this)), 0, 1, "debt");
    }

    function testBuyPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.obligationShares = 100;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.obligationShares = 100;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 shares, uint256 tick, uint256 collateralized) public {
        shares = bound(shares, 1, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        borrowerOffer.obligationShares = shares;
        borrowerOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("seller is unhealthy");
        take(shares, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 shares, uint256 tick, uint256 collateralized) public {
        shares = bound(shares, 1, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, MAX_TICK);
        lenderOffer.obligationShares = shares;
        lenderOffer.tick = tick;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("seller is unhealthy");
        take(shares, borrower, lenderOffer);
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

    function testTakeTwoLeaves(uint256 shares, Offer memory otherOffer) public {
        shares = bound(shares, 0, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, units);
        lenderOffer.obligationShares = shares;

        vm.prank(borrower);
        midnight.take(
            shares,
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

    function testBuySellerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(0, collateral);
        borrowerOffer.obligationShares = shares;
        borrowerOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(midnight.collateralOf(id, borrower, 0), 0);

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, borrowerOffer.callback, true);

        take(shares, lender, borrowerOffer);

        assertEq(midnight.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.obligationShares = shares;
        lenderOffer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        deal(obligation.collaterals[0].token, callback, collateral);

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, callback, true);

        vm.prank(borrower);
        midnight.take(
            shares,
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

    function testSellBuyerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivDown(price, WAD);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.obligationShares = shares;
        lenderOffer.tick = MAX_TICK;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(obligation, borrower, units);

        take(shares, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        (address _otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(_otherLender);
        loanToken.approve(address(midnight), assets);
        address callback = address(new LendCallback());
        borrowerOffer.obligationShares = shares;
        borrowerOffer.tick = MAX_TICK;
        deal(address(loanToken), callback, assets);
        collateralize(obligation, borrower, units);

        vm.prank(_otherLender);
        midnight.take(
            shares,
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
    // - any offer / share take input / 0 trading fee.
    // - sell offer / share take input / > 0 trading fee.
    //
    // Otherwise it fails:
    // - by underflow when the trading fee is > 0, and the offer is a buy offer.

    // fee=0, sell, shares
    function testPriceZero_NoTradingFee_sell() public {
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.obligationShares = shares;
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(shares, lender, borrowerOffer);
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        assertEq(buyerAssets, 0, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.sharesOf(id, lender), shares, "sharesOf");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "debtOf");
    }

    // fee>0, buy, shares
    function testPriceZero_WithTradingFee_buy() public {
        midnight.setObligationTradingFee(id, 1, 1e12);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        lenderOffer.tick = 0;
        lenderOffer.obligationShares = shares;
        collateralize(obligation, borrower, units);
        vm.expectRevert();
        take(shares, borrower, lenderOffer);
    }

    // fee>0, sell, shares
    function testPriceZero_WithTradingFee_sell() public {
        midnight.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.obligationShares = shares;
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(fee, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, expectedUnits);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(shares, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(midnight.sharesOf(id, lender), shares, "sharesOf");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "debtOf");
    }

    // unit input tests.

    function testBuyUnitInput(uint256 targetUnits, uint256 tick) public {
        targetUnits = bound(targetUnits, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        // Convert target units to shares (the taker still specifies shares).
        uint256 obligationShares = targetUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        uint256 expectedUnits = obligationShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivUp(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, expectedUnits);

        // Maker specifies offer in units.
        borrowerOffer.obligationUnits = targetUnits;
        borrowerOffer.obligationShares = 0;
        borrowerOffer.tick = tick;

        take(obligationShares, lender, borrowerOffer);

        assertEq(midnight.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(midnight.consumed(borrower, borrowerOffer.group), expectedUnits, "consumed");
    }

    function testSellUnitInput(uint256 targetUnits, uint256 tick) public {
        targetUnits = bound(targetUnits, 1, maxAssets);
        tick = bound(tick, 0, MAX_TICK);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 obligationShares = targetUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        uint256 expectedUnits = obligationShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1).mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, expectedUnits);

        // Maker specifies offer in units.
        lenderOffer.obligationUnits = targetUnits;
        lenderOffer.obligationShares = 0;
        lenderOffer.tick = tick;

        take(obligationShares, borrower, lenderOffer);

        assertEq(midnight.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(midnight.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(midnight.consumed(lender, lenderOffer.group), expectedUnits, "consumed");
    }

    function testUnitInputInconsistent() public {
        borrowerOffer.obligationUnits = 100;
        borrowerOffer.obligationShares = 100;
        borrowerOffer.tick = MAX_TICK;

        vm.expectRevert("INCONSISTENT_INPUT");
        take(100, lender, borrowerOffer);
    }
}

contract BorrowCallback is ICallbacks {
    bytes public recordedData;

    function onSell(Obligation memory obligation, address seller, uint256, uint256, uint256, uint256, bytes memory data)
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
        uint256 obligationShares,
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
        uint256 obligationShares,
        bytes memory data
    ) external {}

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
