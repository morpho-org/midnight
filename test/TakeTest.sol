// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
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
    bytes32 internal id;
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

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
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
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, lender, buyerAssets, 0, 0, borrowerOffer);

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
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, borrower, buyerAssets, 0, 0, lenderOffer);

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

        take(0, 0, obligationUnits, 0, lender, expectedAssets + 1, 0, 0, borrowerOffer);

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

        take(0, 0, obligationUnits, 0, borrower, expectedAssets + 1, 0, 0, lenderOffer);

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

        take(0, 0, 0, obligationShares, lender, expectedAssets + 1, 0, 0, borrowerOffer);

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

        take(0, 0, 0, obligationShares, borrower, expectedAssets + 1, 0, 0, lenderOffer);

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
        otherLenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, lender, buyerAssets, 0, 0, otherLenderOffer);

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
        lenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherLender, buyerAssets, 0, 0, lenderOffer);

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
        otherLenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, lender, buyerAssets + 1, 0, 0, otherLenderOffer);

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
        lenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherLender, buyerAssets + 1, 0, 0, lenderOffer);

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
        otherLenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, lender, type(uint256).max, 0, 0, otherLenderOffer);

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
        lenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherLender, type(uint256).max, 0, 0, lenderOffer);

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
        take(0, 0, obligationUnits, 0, lender, type(uint256).max, 0, 0, otherLenderOffer);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, otherLender, type(uint256).max, 0, 0, lenderOffer);
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
        borrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherBorrower, buyerAssets, 0, 0, borrowerOffer);

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
        otherBorrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, borrower, buyerAssets, 0, 0, otherBorrowerOffer);

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
        borrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherBorrower, buyerAssets + 1, 0, 0, borrowerOffer);

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
        otherBorrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, borrower, buyerAssets + 1, 0, 0, otherBorrowerOffer);

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
        borrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherBorrower, buyerAssets + 1, 0, 0, borrowerOffer);

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
        otherBorrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, borrower, type(uint256).max, 0, 0, otherBorrowerOffer);

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
        take(0, 0, obligationUnits, 0, borrower, type(uint256).max, 0, 0, otherBorrowerOffer);

        vm.expectRevert(stdError.arithmeticError);
        take(0, 0, obligationUnits, 0, otherBorrower, type(uint256).max, 0, 0, borrowerOffer);
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
        otherLenderOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherBorrower, buyerAssets, 0, 0, otherLenderOffer);

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
        otherBorrowerOffer.tick = tick;

        take(buyerAssets, 0, 0, 0, otherLender, buyerAssets, 0, 0, otherBorrowerOffer);

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
        otherLenderOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherBorrower, buyerAssets + 1, 0, 0, otherLenderOffer);

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
        otherBorrowerOffer.tick = tick;

        take(0, 0, obligationUnits, 0, otherLender, buyerAssets + 1, 0, 0, otherBorrowerOffer);

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

        otherLenderOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherBorrower, type(uint256).max, 0, 0, otherLenderOffer);

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

        otherBorrowerOffer.tick = tick;

        take(0, 0, 0, obligationShares, otherLender, type(uint256).max, 0, 0, otherBorrowerOffer);

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
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick)));

        take(assets, 0, 0, 0, lender, offerAmount, 0, 0, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, lender, offerAmount, 0, 0, borrowerOffer);

        take(secondPassingTake, 0, 0, 0, lender, offerAmount, 0, 0, borrowerOffer);
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
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));

        take(assets, 0, 0, 0, borrower, offerAmount, 0, 0, lenderOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, borrower, offerAmount, 0, 0, lenderOffer);

        take(secondPassingTake, 0, 0, 0, borrower, offerAmount, 0, 0, lenderOffer);
    }

    function testBuyGroupAssets(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupAssets = firstFill + secondFill;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick)));
        collateralize(
            borrowerOffer2.obligation, borrower, secondFill.mulDivDown(WAD, TickLib.tickToPrice(borrowerOffer.tick))
        );

        take(firstFill, 0, 0, 0, lender, groupAssets, 0, 0, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, lender, groupAssets, 0, 0, borrowerOffer2);

        take(secondFill, 0, 0, 0, lender, groupAssets, 0, 0, borrowerOffer2);
    }

    function testSellGroupAssets(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupAssets = firstFill + secondFill;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));
        collateralize(
            lenderOffer2.obligation, borrower, secondFill.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick))
        );

        take(firstFill, 0, 0, 0, borrower, groupAssets, 0, 0, lenderOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, borrower, groupAssets, 0, 0, lenderOffer2);

        take(secondFill, 0, 0, 0, borrower, groupAssets, 0, 0, lenderOffer2);
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
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(0, 0, obligationUnits, 0, lender, 0, offerObligationUnits, 0, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondRevertingTake, 0, lender, 0, offerObligationUnits, 0, borrowerOffer);

        take(0, 0, secondPassingTake, 0, lender, 0, offerObligationUnits, 0, borrowerOffer);
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
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits);
        collateralize(obligation, borrower, offerObligationUnits);

        take(0, 0, obligationUnits, 0, borrower, 0, offerObligationUnits, 0, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondRevertingTake, 0, borrower, 0, offerObligationUnits, 0, lenderOffer);

        take(0, 0, secondPassingTake, 0, borrower, 0, offerObligationUnits, 0, lenderOffer);
    }

    function testBuyGroupUnits(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupUnits = firstFill + secondFill;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(0, 0, firstFill, 0, lender, 0, groupUnits, 0, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondFill + 1, 0, lender, 0, groupUnits, 0, borrowerOffer2);

        take(0, 0, secondFill, 0, lender, 0, groupUnits, 0, borrowerOffer2);
    }

    function testSellGroupUnits(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupUnits = firstFill + secondFill;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(0, 0, firstFill, 0, borrower, 0, groupUnits, 0, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, secondFill + 1, 0, borrower, 0, groupUnits, 0, lenderOffer2);

        take(0, 0, secondFill, 0, borrower, 0, groupUnits, 0, lenderOffer2);
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
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(0, 0, 0, obligationShares, lender, 0, 0, offerObligationShares, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondRevertingTake, lender, 0, 0, offerObligationShares, borrowerOffer);

        take(0, 0, 0, secondPassingTake, lender, 0, 0, offerObligationShares, borrowerOffer);
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
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationShares);
        collateralize(obligation, borrower, offerObligationShares);

        take(0, 0, 0, obligationShares, borrower, 0, 0, offerObligationShares, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondRevertingTake, borrower, 0, 0, offerObligationShares, lenderOffer);

        take(0, 0, 0, secondPassingTake, borrower, 0, 0, offerObligationShares, lenderOffer);
    }

    function testBuyGroupShares(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupShares = firstFill + secondFill;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(0, 0, 0, firstFill, lender, 0, 0, groupShares, borrowerOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondFill + 1, lender, 0, 0, groupShares, borrowerOffer2);

        take(0, 0, 0, secondFill, lender, 0, 0, groupShares, borrowerOffer2);
    }

    function testSellGroupShares(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        uint256 groupShares = firstFill + secondFill;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(0, 0, 0, firstFill, borrower, 0, 0, groupShares, lenderOffer);

        vm.expectRevert("consumed");
        take(0, 0, 0, secondFill + 1, borrower, 0, 0, groupShares, lenderOffer2);

        take(0, 0, 0, secondFill, borrower, 0, 0, groupShares, lenderOffer2);
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
        borrowerOffer.tick = tick1;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivDown(price1, WAD));
        collateralize(obligation, borrower, units);

        take(0, 0, units, 0, address(this), units, 0, 0, borrowerOffer);
        take(0, 0, units, 0, address(this), units, 0, 0, lenderOffer);

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
        borrowerOffer.tick = tick1;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        collateralize(obligation, borrower, units);
        collateralize(obligation, address(this), units);

        take(0, 0, units, 0, address(this), units, 0, 0, lenderOffer);
        take(0, 0, units, 0, address(this), units, 0, 0, borrowerOffer);

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
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, lender, 100, 0, 0, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, borrower, 100, 0, 0, lenderOffer);
    }

    function testBuyUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        borrowerOffer.tick = tick;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, lender, units, 0, 0, borrowerOffer);
    }

    function testSellUnhealthy(uint256 units, uint256 tick, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        lenderOffer.tick = tick;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, borrower, units, 0, 0, lenderOffer);
    }

    // test tree / signatures.

    function testTakeWrongRoot() public {
        vm.expectRevert("invalid signature");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            100,
            0,
            0,
            lenderOffer,
            sig([borrowerOffer], bytes32(0), 100, 0, 0),
            root([lenderOffer]),
            proof([lenderOffer]),
            address(0),
            hex""
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert("invalid signature");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            100,
            0,
            0,
            lenderOffer,
            Signature({v: 0, r: 0, s: 0}),
            root([lenderOffer]),
            proof([lenderOffer]),
            address(0),
            hex""
        );
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.expectRevert("invalid proof");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            100,
            0,
            0,
            lenderOffer,
            sig([lenderOffer], bytes32(0), 100, 0, 0),
            root([lenderOffer]),
            proof,
            address(0),
            hex""
        );
    }

    function testTakeInvalidProofTwoLeaves(Offer memory otherOffer, bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.assume(proof[0] != keccak256(abi.encode(otherOffer)));
        vm.expectRevert("invalid proof");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            100,
            0,
            0,
            lenderOffer,
            sig([lenderOffer, otherOffer], bytes32(0), 100, 0, 0),
            root([lenderOffer, otherOffer]),
            proof,
            address(0),
            hex""
        );
    }

    function testTakeTwoLeaves(uint256 assets, Offer memory otherOffer) public {
        assets = bound(assets, 0, maxAssets);
        deal(address(loanToken), lender, assets);
        collateralize(obligation, borrower, assets.mulDivDown(WAD, TickLib.tickToPrice(lenderOffer.tick)));

        morphoV2.take(
            assets,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            assets,
            0,
            0,
            lenderOffer,
            sig([lenderOffer, otherOffer], bytes32(0), assets, 0, 0),
            root([lenderOffer, otherOffer]),
            proof([lenderOffer, otherOffer]),
            address(0),
            hex""
        );
    }

    // test callbacks.

    function testBuySellerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        uint256 collateral = assets.mulDivUp(WAD, obligation.collaterals[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(obligation.collaterals[0].token, collateral);
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token), 0);

        take(assets, 0, 0, 0, lender, assets, 0, 0, borrowerOffer);

        assertEq(morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        uint256 collateral = assets.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.tick = TICK_RANGE;
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, callback, collateral);

        morphoV2.take(
            assets,
            0,
            0,
            0,
            borrower,
            bytes32(0),
            address(loanToken),
            assets,
            0,
            0,
            lenderOffer,
            sig([lenderOffer], bytes32(0), assets, 0, 0),
            root([lenderOffer]),
            proof([lenderOffer]),
            callback,
            abi.encode(obligation.collaterals[0].token, collateral)
        );
        assertEq(morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(obligation.collaterals[0].token, collateral));
    }

    function testSellBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(obligation, borrower, assets);

        take(assets, 0, 0, 0, borrower, assets, 0, 0, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        (address otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), assets);
        address callback = address(new LendCallback());
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), callback, assets);
        collateralize(obligation, borrower, assets);

        morphoV2.take(
            assets,
            0,
            0,
            0,
            otherLender,
            bytes32(0),
            address(loanToken),
            assets,
            0,
            0,
            borrowerOffer,
            sig([borrowerOffer], bytes32(0), assets, 0, 0),
            root([borrowerOffer]),
            proof([borrowerOffer]),
            callback,
            abi.encode(address(loanToken), assets)
        );
        assertEq(LendCallback(callback).recordedData(), abi.encode(address(loanToken), assets));
    }
}

contract BorrowCallback is ICallbacks {
    bytes public recordedData;

    function onSell(Obligation memory obligation, address seller, uint256, uint256, uint256, uint256, bytes memory data)
        external
    {
        recordedData = data;
        (address collateralToken, uint256 amount) = abi.decode(data, (address, uint256));
        ERC20(collateralToken).approve(msg.sender, amount);
        MorphoV2(msg.sender).supplyCollateral(obligation, collateralToken, amount, seller);
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

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
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
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}
