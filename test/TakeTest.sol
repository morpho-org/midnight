// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";

contract TakeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    Offer internal otherLenderOffer;
    Offer internal otherBorrowerOffer;

    uint256 internal maxAssets = 1e33; // to refine.
    uint256 internal initialUnits;
    uint256 internal initialShares;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.minCollatValue = 0;

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.obligation = obligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = TICK_RANGE;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = morphoV2.totalUnits(id);
        initialShares = morphoV2.totalShares(id);
    }

    // tests.

    // path 1: Lender enters + borrower enters.

    function testBuyAssetsInput1(uint256 buyerAssets, uint256 tick) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        borrowerOffer.assets = buyerAssets;
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(id, lender), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), buyerAssets, "borrower consumed");
    }

    function testSellAssetsInput1(uint256 buyerAssets, uint256 tick) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        lenderOffer.assets = buyerAssets;
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(id, lender), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), buyerAssets, "lender consumed");
    }

    function testBuyObligationUnitsInput1(uint256 obligationUnits, uint256 tick) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.assets = expectedAssets + 1;

        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(id, lender), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + obligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), expectedAssets, "borrower consumed");
    }

    function testSellObligationUnitsInput1(uint256 obligationUnits, uint256 tick) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);
        lenderOffer.assets = expectedAssets + 1;

        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(id, lender), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + obligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), expectedAssets, "lender consumed");
    }

    function testBuyObligationSharesInput1(uint256 obligationShares, uint256 tick) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationShares);
        borrowerOffer.assets = expectedAssets + 1;

        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), expectedAssets, "borrower consumed");
    }

    function testSellObligationSharesInput1(uint256 obligationShares, uint256 tick) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationShares);
        lenderOffer.assets = expectedAssets + 1;

        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(id, lender), obligationShares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), expectedAssets, "lender consumed");
    }

    // path 2: Lender enters + lender exits.

    function testBuyAssetsInput2(uint256 buyerAssets, uint256 tick, uint256 otherLenderUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets);
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = buyerAssets;
        otherLenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), expectedShares, 1, "lender shares");
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput2(uint256 buyerAssets, uint256 tick, uint256 otherLenderUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets);
        lenderOffer.assets = buyerAssets;
        lenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), expectedShares, 1, "lender shares");
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(lenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput2(uint256 obligationUnits, uint256 tick, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets);
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = buyerAssets + 1;
        otherLenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), expectedShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput2(uint256 obligationUnits, uint256 tick, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        vm.assume(obligationUnits <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets);
        lenderOffer.assets = buyerAssets + 1;
        lenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), expectedShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(lenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput2(uint256 obligationShares, uint256 tick, uint256 otherLenderUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        vm.assume(obligationShares <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1); // TODO fix
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), obligationShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - obligationShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(lender), 1, 1, "lender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "other lender balance");
        assertApproxEqAbs(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput2(uint256 obligationShares, uint256 tick, uint256 otherLenderUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        vm.assume(obligationShares <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        deal(address(loanToken), lender, buyerAssets + 1); // TODO fix
        lenderOffer.assets = type(uint256).max;
        lenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), obligationShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - obligationShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(lender), 1, 1, "lender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "other lender balance");
        assertApproxEqAbs(morphoV2.consumed(lenderOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testCannotCrossTopDown(uint256 obligationUnits, uint256 otherLenderUnits) public {
        otherLenderUnits = bound(otherLenderUnits, 1, maxAssets - 1);
        obligationUnits = bound(obligationUnits, otherLenderUnits + 1, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, lender, otherLenderOffer);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, otherLender, lenderOffer);
    }

    // path 3: Borrower exits + borrower enters.

    function testBuyAssetsInput3(uint256 buyerAssets, uint256 tick, uint256 otherBorrowerDebt) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        otherBorrowerDebt = bound(otherBorrowerDebt, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, expectedUnits);
        borrowerOffer.assets = buyerAssets;
        borrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherBorrower, borrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower shares");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput3(uint256 buyerAssets, uint256 tick, uint256 otherBorrowerDebt) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        otherBorrowerDebt = bound(otherBorrowerDebt, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, expectedUnits);
        otherBorrowerOffer.assets = buyerAssets;
        otherBorrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput3(uint256 obligationUnits, uint256 tick, uint256 otherBorrowerDebt) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.assets = buyerAssets + 1;
        borrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherBorrower, borrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput3(uint256 obligationUnits, uint256 tick, uint256 otherBorrowerDebt) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, obligationUnits);
        otherBorrowerOffer.assets = buyerAssets + 1;
        otherBorrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), obligationUnits, "borrower debt");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput3(uint256 obligationShares, uint256 tick, uint256 otherBorrowerDebt) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, obligationShares);
        borrowerOffer.assets = buyerAssets + 1;
        borrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherBorrower, borrowerOffer);

        assertApproxEqAbs(morphoV2.debtOf(id, borrower), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(borrower), buyerAssets, 1, "borrower balance");
        assertApproxEqAbs(
            loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, 1, "otherBorrower balance"
        );
        assertApproxEqAbs(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput3(uint256 obligationShares, uint256 tick, uint256 otherBorrowerDebt) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        collateralize(obligation, borrower, obligationShares);
        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, borrower, otherBorrowerOffer);

        assertApproxEqAbs(morphoV2.debtOf(id, borrower), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            morphoV2.debtOf(id, otherBorrower), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(borrower), buyerAssets, 1, "borrower balance");
        assertApproxEqAbs(
            loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, 1, "otherBorrower balance"
        );
        assertApproxEqAbs(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testCannotCrossBottomUp(uint256 obligationUnits, uint256 otherUnits) public {
        otherUnits = bound(otherUnits, 1, maxAssets - 1);
        obligationUnits = bound(obligationUnits, otherUnits + 1, maxAssets);
        setupOtherUsers(obligation, otherUnits);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, borrower, otherBorrowerOffer);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, otherBorrower, borrowerOffer);
    }

    // path 4: Borrower exits + lender exits.

    function testBuyAssetsInput4(uint256 buyerAssets, uint256 tick, uint256 existingUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        otherLenderOffer.assets = buyerAssets;
        otherLenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput4(uint256 buyerAssets, uint256 tick, uint256 existingUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        otherBorrowerOffer.assets = buyerAssets;
        otherBorrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput4(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        vm.assume(price > 0.01 ether);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        otherLenderOffer.assets = buyerAssets + 1;
        otherLenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - obligationUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - obligationUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput4(uint256 obligationUnits, uint256 tick, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        otherBorrowerOffer.assets = buyerAssets + 1;
        otherBorrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - obligationUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - obligationUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput4(uint256 obligationShares, uint256 tick, uint256 existingUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);

        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - obligationShares, 1, "total shares"
        );
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "otherLender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, 1, "otherBorrower balance");
        assertApproxEqAbs(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput4(uint256 obligationShares, uint256 tick, uint256 existingUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);

        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(id, otherLender), otherLenderShares - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(id, otherBorrower), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - obligationShares, 1, "total shares"
        );
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "otherLender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, 1, "otherBorrower balance");
        assertApproxEqAbs(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    // group tests.

    // with assets
    function testBuyConsumedAssets(
        uint256 assets,
        uint256 offerAmount,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        assets = bound(assets, 0, maxAssets - 1);
        offerAmount = bound(offerAmount, assets, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerAmount - assets + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerAmount - assets);
        borrowerOffer.assets = offerAmount;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick)));

        take(assets, 0, 0, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, lender, borrowerOffer);

        take(secondPassingTake, 0, 0, 0, lender, borrowerOffer);
    }

    function testSellConsumedAssets(
        uint256 assets,
        uint256 offerAmount,
        uint256 secondRevertingTake,
        uint256 secondPassingTake
    ) public {
        assets = bound(assets, 0, maxAssets - 1);
        offerAmount = bound(offerAmount, assets, maxAssets - 1);
        secondRevertingTake = bound(secondRevertingTake, offerAmount - assets + 1, maxAssets);
        secondPassingTake = bound(secondPassingTake, 0, offerAmount - assets);
        lenderOffer.assets = offerAmount;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));

        take(assets, 0, 0, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, borrower, lenderOffer);

        take(secondPassingTake, 0, 0, 0, borrower, lenderOffer);
    }

    function testBuyGroupAssets(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.assets = firstFill + secondFill;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick)));
        collateralize(
            borrowerOffer2.obligation, borrower, secondFill.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick))
        );

        take(firstFill, 0, 0, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, lender, borrowerOffer2);

        take(secondFill, 0, 0, 0, lender, borrowerOffer2);
    }

    function testSellGroupAssets(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.assets = firstFill + secondFill;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));
        collateralize(
            lenderOffer2.obligation, borrower, secondFill.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick))
        );

        take(firstFill, 0, 0, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, borrower, lenderOffer2);

        take(secondFill, 0, 0, 0, borrower, lenderOffer2);
    }

    // with obligation units
    function testBuyConsumedUnits(
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
        borrowerOffer.assets = 0;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondRevertingTake, 0, lender, borrowerOffer);

        take(0, 0, secondPassingTake, 0, lender, borrowerOffer);
    }

    function testSellConsumedUnits(
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
        lenderOffer.assets = 0;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondRevertingTake, 0, borrower, lenderOffer);

        take(0, 0, secondPassingTake, 0, borrower, lenderOffer);
    }

    function testBuyGroupUnits(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.obligationUnits = firstFill + secondFill;
        borrowerOffer.assets = 0;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(0, 0, firstFill, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondFill + 1, 0, lender, borrowerOffer2);

        take(0, 0, secondFill, 0, lender, borrowerOffer2);
    }

    function testSellGroupUnits(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.obligationUnits = firstFill + secondFill;
        lenderOffer.assets = 0;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(0, 0, firstFill, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondFill + 1, 0, borrower, lenderOffer2);

        take(0, 0, secondFill, 0, borrower, lenderOffer2);
    }

    // with obligation shares
    function testBuyConsumedShares(
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
        borrowerOffer.assets = 0;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondRevertingTake, lender, borrowerOffer);

        take(0, 0, 0, secondPassingTake, lender, borrowerOffer);
    }

    function testSellConsumedShares(
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
        lenderOffer.assets = 0;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondRevertingTake, borrower, lenderOffer);

        take(0, 0, 0, secondPassingTake, borrower, lenderOffer);
    }

    function testBuyGroupShares(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.obligationShares = firstFill + secondFill;
        borrowerOffer.assets = 0;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(0, 0, 0, firstFill, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondFill + 1, lender, borrowerOffer2);

        take(0, 0, 0, secondFill, lender, borrowerOffer2);
    }

    function testSellGroupShares(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.obligationShares = firstFill + secondFill;
        lenderOffer.assets = 0;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(0, 0, 0, firstFill, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondFill + 1, borrower, lenderOffer2);

        take(0, 0, 0, secondFill, borrower, lenderOffer2);
    }

    // other tests.

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatch(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, 600, TICK_RANGE);
        tick2 = bound(tick2, 600, TICK_RANGE);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price1 > price2);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.assets = units;
        borrowerOffer.tick = tick1;
        lenderOffer.assets = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivDown(price1, WAD));
        collateralize(obligation, borrower, units);

        take(0, 0, units, 0, address(this), borrowerOffer);
        take(0, 0, units, 0, address(this), lenderOffer);

        assertEq(morphoV2.sharesOf(id, address(this)), 0, "shares");
        assertEq(morphoV2.debtOf(id, address(this)), 0, "debt");
        assertEq(morphoV2.sharesOf(id, lender), units.mulDivDown(initialShares + 1, initialUnits + 1), "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), units, "borrower debt");
        assertEq(loanToken.balanceOf(address(this)), units.mulDivDown(price2, WAD), "balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(borrower), units.mulDivDown(price1, WAD), "borrower balance");
        assertEq(morphoV2.consumed(lender, 0), units.mulDivDown(price2, WAD), "lender consumed");
        assertEq(morphoV2.consumed(borrower, 0), units.mulDivDown(price1, WAD), "borrower consumed");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 units, uint256 tick1, uint256 tick2) public {
        units = bound(units, 1, maxAssets);
        tick1 = bound(tick1, 600, TICK_RANGE);
        tick2 = bound(tick2, 600, TICK_RANGE);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price2 > price1);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        borrowerOffer.assets = units;
        borrowerOffer.tick = tick1;
        lenderOffer.assets = units;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        collateralize(obligation, borrower, units);
        collateralize(obligation, address(this), units);

        take(0, 0, units, 0, address(this), lenderOffer);
        take(0, 0, units, 0, address(this), borrowerOffer);

        assertEq(morphoV2.sharesOf(id, address(this)), 0, "shares");
        assertEq(morphoV2.debtOf(id, address(this)), 0, "debt");
        assertEq(morphoV2.sharesOf(id, lender), units.mulDivDown(initialShares + 1, initialUnits + 1), "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), units, "borrower debt");
        assertEq(
            loanToken.balanceOf(address(this)), units.mulDivDown(price2, WAD) - units.mulDivDown(price1, WAD), "balance"
        );
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(borrower), units.mulDivDown(price1, WAD), "borrower balance");
        assertEq(morphoV2.consumed(lender, 0), units.mulDivDown(price2, WAD), "lender consumed");
        assertEq(morphoV2.consumed(borrower, 0), units.mulDivDown(price1, WAD), "borrower consumed");
    }

    function testBuyPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.assets = 100;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.assets = 100;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        borrowerOffer.assets = units;
        borrowerOffer.tick = tick;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        lenderOffer.assets = units;
        lenderOffer.tick = tick;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, borrower, lenderOffer);
    }

    function testSession() public {
        vm.prank(lender);
        morphoV2.shuffleSession();

        vm.expectRevert("invalid session");
        take(100, 0, 0, 0, borrower, lenderOffer);
    }

    // test tree / signatures.

    function testTakeWrongRoot() public {
        vm.expectRevert("invalid signature");
        vm.prank(borrower);
        morphoV2.take(
            100,
            0,
            0,
            0,
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
        morphoV2.take(
            100,
            0,
            0,
            0,
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
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof
        );
    }

    function testTakeInvalidProofTwoLeaves(Offer memory otherOffer, bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.assume(proof[0] != keccak256(abi.encode(otherOffer)));
        vm.expectRevert("invalid proof");
        vm.prank(borrower);
        morphoV2.take(
            100,
            0,
            0,
            0,
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

    function testTakeTwoLeaves(uint256 assets, Offer memory otherOffer) public {
        assets = bound(assets, 0, maxAssets);
        deal(address(loanToken), lender, assets);
        collateralize(obligation, borrower, assets.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));
        lenderOffer.assets = assets;

        vm.prank(borrower);
        morphoV2.take(
            assets,
            0,
            0,
            0,
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

    function testBuySellerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        uint256 collateral = assets.mulDivUp(WAD, obligation.collaterals[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(0, collateral);
        borrowerOffer.assets = assets;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(morphoV2.collateralOf(id, borrower, 0), 0);

        take(assets, 0, 0, 0, lender, borrowerOffer);

        assertEq(morphoV2.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        uint256 collateral = assets.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.assets = assets;
        lenderOffer.tick = TICK_RANGE;
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, callback, collateral);

        vm.prank(borrower);
        morphoV2.take(
            assets,
            0,
            0,
            0,
            borrower,
            callback,
            abi.encode(0, collateral),
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );
        assertEq(morphoV2.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(0, collateral));
    }

    function testSellBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.assets = assets;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(obligation, borrower, assets);

        take(assets, 0, 0, 0, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        (address _otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(_otherLender);
        loanToken.approve(address(morphoV2), assets);
        address callback = address(new LendCallback());
        borrowerOffer.assets = assets;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), callback, assets);
        collateralize(obligation, borrower, assets);

        vm.prank(_otherLender);
        morphoV2.take(
            assets,
            0,
            0,
            0,
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
    // - any offer / unit or share take input / 0 trading fee.
    // - sell offer / unit, share or buyer take input / > 0 trading fee.
    //
    // Otherwise it fails:
    // - by underflow when the trading fee is > 0, and the offer is a buy offer.
    // - by division by zero in all other cases.

    // fee=0, sell, buyer assets
    function testPriceZero_NoTradingFee_sell_buyerAssets() public {
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 1e18;
        deal(address(loanToken), lender, 1e18);
        collateralize(obligation, borrower, 1e18);
        vm.expectRevert();
        take(1e18, 0, 0, 0, lender, borrowerOffer);
    }

    // fee=0, sell, seller assets
    function testPriceZero_NoTradingFee_sell_sellerAssets() public {
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 1e18;
        collateralize(obligation, borrower, 1e18);
        vm.expectRevert();
        take(0, 1e18, 0, 0, lender, borrowerOffer);
    }

    // fee=0, sell, units
    function testPriceZero_NoTradingFee_sell_units() public {
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 0;
        borrowerOffer.obligationUnits = units;
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(0, 0, units, 0, lender, borrowerOffer);
        assertEq(buyerAssets, 0, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), units, "debtOf");
    }

    // fee=0, sell, shares
    function testPriceZero_NoTradingFee_sell_shares() public {
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 0;
        borrowerOffer.obligationShares = shares;
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(0, 0, 0, shares, lender, borrowerOffer);
        uint256 expectedUnits = shares.mulDivDown(initialUnits + 1, initialShares + 1);
        assertEq(buyerAssets, 0, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "debtOf");
    }

    // fee>0, buy, units
    function testPriceZero_WithTradingFee_buy_units() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        lenderOffer.tick = 0;
        lenderOffer.assets = 0;
        lenderOffer.obligationUnits = 1e18;
        collateralize(obligation, borrower, 1e18);
        vm.expectRevert();
        take(0, 0, 1e18, 0, borrower, lenderOffer);
    }

    // fee>0, sell, buyer assets
    function testPriceZero_WithTradingFee_sell_buyerAssets() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = fee;
        deal(address(loanToken), lender, fee);
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(fee, 0, 0, 0, lender, borrowerOffer);
        assertEq(buyerAssets, fee, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), units, "debtOf");
    }

    // fee>0, sell, seller assets
    function testPriceZero_WithTradingFee_sell_sellerAssets() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 1e18;
        collateralize(obligation, borrower, 1e18);
        vm.expectRevert();
        take(0, 1e18, 0, 0, lender, borrowerOffer);
    }

    // fee>0, sell, units
    function testPriceZero_WithTradingFee_sell_units() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 0;
        borrowerOffer.obligationUnits = units;
        uint256 expectedBuyerAssets = units.mulDivDown(fee, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, units);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(0, 0, units, 0, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), units, "debtOf");
    }

    // fee>0, sell, shares
    function testPriceZero_WithTradingFee_sell_shares() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        borrowerOffer.tick = 0;
        borrowerOffer.assets = 0;
        borrowerOffer.obligationShares = shares;
        uint256 expectedUnits = shares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivDown(fee, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, expectedUnits);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(0, 0, 0, shares, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "debtOf");
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
        MorphoV2(msg.sender).supplyCollateral(obligation, collateralIndex, amount, seller);
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
