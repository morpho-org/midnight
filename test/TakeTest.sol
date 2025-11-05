// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {ORACLE_PRICE_SCALE, WAD} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    Offer internal otherLenderOffer;
    Offer internal otherBorrowerOffer;

    uint256 internal maxAssets = 1e36; // to refine.
    uint256 internal initialUnits;
    uint256 internal initialShares;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = keccak256(abi.encode(obligation));

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.startPrice = 1 ether;
        otherLenderOffer.expiryPrice = 1 ether;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.obligation = obligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.startPrice = 1 ether;
        otherBorrowerOffer.expiryPrice = 1 ether;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = morphoV2.totalUnits(id);
        initialShares = morphoV2.totalShares(id);
    }

    // tests.

    // path 1: Lender enters + borrower enters.

    function testBuyAssetsInput1(uint256 buyerAssets, uint256 price) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;
        borrowerOffer.assets = buyerAssets;
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(lender, id), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), buyerAssets, "borrower consumed");
    }

    function testSellAssetsInput1(uint256 buyerAssets, uint256 price) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;
        lenderOffer.assets = buyerAssets;
        deal(address(loanToken), lender, buyerAssets);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        collateralize(obligation, borrower, expectedUnits);

        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(lender, id), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), buyerAssets, "lender consumed");
    }

    function testBuyObligationUnitsInput1(uint256 obligationUnits, uint256 price) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;
        uint256 expectedAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.assets = expectedAssets + 1;

        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(lender, id), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), obligationUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + obligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), expectedAssets, "borrower consumed");
    }

    function testSellObligationUnitsInput1(uint256 obligationUnits, uint256 price) public {
        obligationUnits = bound(obligationUnits, 1, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;
        uint256 expectedAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationUnits);
        lenderOffer.assets = expectedAssets + 1;

        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(lender, id), expectedShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), obligationUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + obligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + expectedShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), expectedAssets, "lender consumed");
    }

    function testBuyObligationSharesInput1(uint256 obligationShares, uint256 price) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationShares);
        borrowerOffer.assets = expectedAssets + 1;

        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(lender, id), obligationShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), expectedAssets, "borrower consumed");
    }

    function testSellObligationSharesInput1(uint256 obligationShares, uint256 price) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 expectedAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedAssets);
        collateralize(obligation, borrower, obligationShares);
        lenderOffer.assets = expectedAssets + 1;

        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(lender, id), obligationShares, "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + obligationShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), expectedAssets, "lender consumed");
    }

    // path 2: Lender enters + lender exits.

    function testBuyAssetsInput2(uint256 buyerAssets, uint256 price, uint256 otherLenderUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets);
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = buyerAssets;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), expectedShares, 1, "lender shares");
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput2(uint256 buyerAssets, uint256 price, uint256 otherLenderUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets);
        lenderOffer.assets = buyerAssets;
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), expectedShares, 1, "lender shares");
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(lenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput2(uint256 obligationUnits, uint256 price, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets);
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = buyerAssets + 1;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), expectedShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput2(uint256 obligationUnits, uint256 price, uint256 otherLenderUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        vm.assume(obligationUnits <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets);
        lenderOffer.assets = buyerAssets + 1;
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), expectedShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "other lender balance");
        assertEq(morphoV2.consumed(lenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput2(uint256 obligationShares, uint256 price, uint256 otherLenderUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        vm.assume(obligationShares <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets + 1); // TODO fix
        otherLenderOffer.buy = false;
        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), obligationShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - obligationShares, 1, "other lender shares"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherLenderUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(lender), 1, 1, "lender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "other lender balance");
        assertApproxEqAbs(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput2(uint256 obligationShares, uint256 price, uint256 otherLenderUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        vm.assume(obligationShares <= maxAssets);
        otherLenderUnits = bound(otherLenderUnits, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        deal(address(loanToken), lender, buyerAssets + 1); // TODO fix
        lenderOffer.assets = type(uint256).max;
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(lender, id), obligationShares, 1, "lender shares"); // TODO: approx
        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - obligationShares, 1, "other lender shares"
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

    function testBuyAssetsInput3(uint256 buyerAssets, uint256 price, uint256 otherBorrowerDebt) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        otherBorrowerDebt = bound(otherBorrowerDebt, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, expectedUnits);
        borrowerOffer.assets = buyerAssets;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, otherBorrower, borrowerOffer);

        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower shares");
        assertEq(morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - expectedUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput3(uint256 buyerAssets, uint256 price, uint256 otherBorrowerDebt) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        otherBorrowerDebt = bound(otherBorrowerDebt, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, expectedUnits);
        otherBorrowerOffer.assets = buyerAssets;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(borrower, id), expectedUnits, "borrower debt");
        assertEq(morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - expectedUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput3(uint256 obligationUnits, uint256 price, uint256 otherBorrowerDebt) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, obligationUnits);
        borrowerOffer.assets = buyerAssets + 1;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, otherBorrower, borrowerOffer);

        assertEq(morphoV2.debtOf(borrower, id), obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput3(uint256 obligationUnits, uint256 price, uint256 otherBorrowerDebt) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationUnits, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, obligationUnits);
        otherBorrowerOffer.assets = buyerAssets + 1;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(borrower, id), obligationUnits, "borrower debt");
        assertEq(morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - obligationUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), buyerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput3(uint256 obligationShares, uint256 price, uint256 otherBorrowerDebt) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, obligationShares);
        borrowerOffer.assets = buyerAssets + 1;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, otherBorrower, borrowerOffer);

        assertApproxEqAbs(morphoV2.debtOf(borrower, id), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertEq(morphoV2.totalUnits(id), initialUnits + otherBorrowerDebt, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + otherLenderShares, "total shares");
        assertApproxEqAbs(loanToken.balanceOf(borrower), buyerAssets, 1, "borrower balance");
        assertApproxEqAbs(
            loanToken.balanceOf(otherBorrower), otherBorrowerDebt - buyerAssets, 1, "otherBorrower balance"
        );
        assertApproxEqAbs(morphoV2.consumed(borrowerOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput3(uint256 obligationShares, uint256 price, uint256 otherBorrowerDebt) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        otherBorrowerDebt = bound(otherBorrowerDebt, obligationShares, maxAssets);
        setupOtherUsers(obligation, otherBorrowerDebt);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        collateralize(obligation, borrower, obligationShares);
        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, borrower, otherBorrowerOffer);

        assertApproxEqAbs(morphoV2.debtOf(borrower, id), expectedUnits, 1, "borrower debt");
        assertApproxEqAbs(
            morphoV2.debtOf(otherBorrower, id), otherBorrowerDebt - expectedUnits, 1, "otherBorrower debt"
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

    function testBuyAssetsInput4(uint256 buyerAssets, uint256 price, uint256 existingUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        otherLenderOffer.assets = buyerAssets;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellAssetsInput4(uint256 buyerAssets, uint256 price, uint256 existingUnits) public {
        buyerAssets = bound(buyerAssets, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedShares = expectedUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, expectedUnits, max(expectedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        otherBorrowerOffer.assets = buyerAssets;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(buyerAssets, 0, 0, 0, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationUnitsInput4(uint256 obligationUnits, uint256 price, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        otherLenderOffer.assets = buyerAssets + 1;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - obligationUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - obligationUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testSellObligationUnitsInput4(uint256 obligationUnits, uint256 price, uint256 existingUnits) public {
        obligationUnits = bound(obligationUnits, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 buyerAssets = obligationUnits.mulDivDown(price, WAD);
        uint256 expectedShares = obligationUnits.mulDivDown(initialShares + 1, initialUnits + 1);
        existingUnits = bound(existingUnits, obligationUnits, max(obligationUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);
        otherBorrowerOffer.assets = buyerAssets + 1;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(0, 0, obligationUnits, 0, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - expectedShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - obligationUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - obligationUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - expectedShares, 1, "total shares"
        );
        assertEq(loanToken.balanceOf(otherLender), buyerAssets, "otherLender balance");
        assertEq(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, "otherBorrower balance");
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, "maker consumed");
    }

    function testBuyObligationSharesInput4(uint256 obligationShares, uint256 price, uint256 existingUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);

        otherLenderOffer.assets = type(uint256).max;
        otherLenderOffer.startPrice = price;
        otherLenderOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - obligationShares, 1, "total shares"
        );
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "otherLender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, 1, "otherBorrower balance");
        assertApproxEqAbs(morphoV2.consumed(otherLenderOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    function testSellObligationSharesInput4(uint256 obligationShares, uint256 price, uint256 existingUnits) public {
        obligationShares = bound(obligationShares, 0, maxAssets);
        price = bound(price, 0.01 ether, 1 ether);
        uint256 expectedUnits = obligationShares.mulDivDown(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = expectedUnits.mulDivDown(price, WAD);
        existingUnits = bound(existingUnits, obligationShares, max(obligationShares, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(otherLender, id);

        otherBorrowerOffer.assets = type(uint256).max;
        otherBorrowerOffer.startPrice = price;
        otherBorrowerOffer.expiryPrice = price;

        take(0, 0, 0, obligationShares, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(
            morphoV2.sharesOf(otherLender, id), otherLenderShares - obligationShares, 1, "otherLender shares"
        );
        assertApproxEqAbs(morphoV2.debtOf(otherBorrower, id), existingUnits - expectedUnits, 1, "otherBorrower debt");
        assertApproxEqAbs(morphoV2.totalUnits(id), initialUnits + existingUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(
            morphoV2.totalShares(id), initialShares + otherLenderShares - obligationShares, 1, "total shares"
        );
        assertApproxEqAbs(loanToken.balanceOf(otherLender), buyerAssets, 1, "otherLender balance");
        assertApproxEqAbs(loanToken.balanceOf(otherBorrower), existingUnits - buyerAssets, 1, "otherBorrower balance");
        assertApproxEqAbs(morphoV2.consumed(otherBorrowerOffer.maker, 0), buyerAssets, 1, "maker consumed");
    }

    // group tests.

    function testBuyConsumed(
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
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount);

        take(assets, 0, 0, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, lender, borrowerOffer);

        take(secondPassingTake, 0, 0, 0, lender, borrowerOffer);
    }

    function testSellConsumed(
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
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lender, offerAmount);
        collateralize(obligation, borrower, offerAmount);

        take(assets, 0, 0, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondRevertingTake, 0, 0, 0, borrower, lenderOffer);

        take(secondPassingTake, 0, 0, 0, borrower, lenderOffer);
    }

    function testBuyGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        borrowerOffer.assets = firstFill + secondFill;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(borrowerOffer2.obligation, borrower, secondFill);

        take(firstFill, 0, 0, 0, lender, borrowerOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, lender, borrowerOffer2);

        take(secondFill, 0, 0, 0, lender, borrowerOffer2);
    }

    function testSellGroup(uint256 firstFill, uint256 secondFill) public {
        firstFill = bound(firstFill, 0, maxAssets);
        secondFill = bound(secondFill, 0, maxAssets);
        lenderOffer.assets = firstFill + secondFill;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstFill + secondFill);
        collateralize(obligation, borrower, firstFill);
        collateralize(lenderOffer2.obligation, borrower, secondFill);

        take(firstFill, 0, 0, 0, borrower, lenderOffer);

        vm.expectRevert("consumed");
        take(secondFill + 1, 0, 0, 0, borrower, lenderOffer2);

        take(secondFill, 0, 0, 0, borrower, lenderOffer2);
    }

    // other tests.

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatch(uint256 units, uint256 price1, uint256 price2) public {
        units = bound(units, 1, maxAssets);
        price1 = bound(price1, 0.1 ether, 1 ether);
        price2 = bound(price2, 0.1 ether, 1 ether);
        vm.assume(price1 < price2);
        borrowerOffer.assets = units;
        borrowerOffer.startPrice = price1;
        borrowerOffer.expiryPrice = price1;
        lenderOffer.assets = units;
        lenderOffer.startPrice = price2;
        lenderOffer.expiryPrice = price2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        deal(address(loanToken), address(this), units.mulDivDown(price1, WAD));
        collateralize(obligation, borrower, units);

        take(0, 0, units, 0, address(this), borrowerOffer);
        take(0, 0, units, 0, address(this), lenderOffer);

        assertEq(morphoV2.sharesOf(address(this), id), 0, "shares");
        assertEq(morphoV2.debtOf(address(this), id), 0, "debt");
        assertEq(morphoV2.sharesOf(lender, id), units.mulDivDown(initialShares + 1, initialUnits + 1), "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), units, "borrower debt");
        assertEq(loanToken.balanceOf(address(this)), units.mulDivDown(price2, WAD), "balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(borrower), units.mulDivDown(price1, WAD), "borrower balance");
        assertEq(morphoV2.consumed(lender, 0), units.mulDivDown(price2, WAD), "lender consumed");
        assertEq(morphoV2.consumed(borrower, 0), units.mulDivDown(price1, WAD), "borrower consumed");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 units, uint256 price1, uint256 price2) public {
        units = bound(units, 1, maxAssets);
        price1 = bound(price1, 0.1 ether, 1 ether);
        price2 = bound(price2, 0.1 ether, 1 ether);
        vm.assume(price1 < price2);
        borrowerOffer.assets = units;
        borrowerOffer.startPrice = price1;
        borrowerOffer.expiryPrice = price1;
        lenderOffer.assets = units;
        lenderOffer.startPrice = price2;
        lenderOffer.expiryPrice = price2;

        deal(address(loanToken), lender, units.mulDivDown(price2, WAD));
        collateralize(obligation, borrower, units);
        collateralize(obligation, address(this), units);

        take(0, 0, units, 0, address(this), lenderOffer);
        take(0, 0, units, 0, address(this), borrowerOffer);

        assertEq(morphoV2.sharesOf(address(this), id), 0, "shares");
        assertEq(morphoV2.debtOf(address(this), id), 0, "debt");
        assertEq(morphoV2.sharesOf(lender, id), units.mulDivDown(initialShares + 1, initialUnits + 1), "lender shares");
        assertEq(morphoV2.debtOf(borrower, id), units, "borrower debt");
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
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.assets = 100;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lender, 100);
        collateralize(obligation, borrower, 100);

        take(100, 0, 0, 0, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 units, uint256 price, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        price = bound(price, 0.01 ether, 1 ether);
        borrowerOffer.assets = units;
        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 units, uint256 price, uint256 collateralized) public {
        units = bound(units, 1, maxAssets);
        collateralized = bound(collateralized, 0, units / 2);
        price = bound(price, 0.01 ether, 1 ether);
        lenderOffer.assets = units;
        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(0, 0, units, 0, borrower, lenderOffer);
    }

    function testTakeInconsistentPrices(uint256 startPrice, uint256 expiryPrice) public {
        vm.assume(startPrice != expiryPrice);
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = lenderOffer.start;
        lenderOffer.startPrice = startPrice;
        lenderOffer.expiryPrice = expiryPrice;
        vm.expectRevert("inconsistent prices");
        take(100, 0, 0, 0, borrower, lenderOffer);
        vm.expectRevert("inconsistent prices");
        take(0, 100, 0, 0, borrower, lenderOffer);
        vm.expectRevert("inconsistent prices");
        take(0, 0, 100, 0, borrower, lenderOffer);
        vm.expectRevert("inconsistent prices");
        take(0, 0, 0, 100, borrower, lenderOffer);
    }

    function testNonce() public {
        vm.prank(lender);
        morphoV2.shuffleNonce();

        vm.expectRevert("invalid nonce");
        take(100, 0, 0, 0, borrower, lenderOffer);
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
            lenderOffer,
            sig([borrowerOffer]),
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
            100, 0, 0, 0, borrower, lenderOffer, sig([lenderOffer]), root([lenderOffer]), proof, address(0), hex""
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
            lenderOffer,
            sig([lenderOffer, otherOffer]),
            root([lenderOffer, otherOffer]),
            proof,
            address(0),
            hex""
        );
    }

    function testTakeTwoLeaves(uint256 assets, Offer memory otherOffer) public {
        assets = bound(assets, 0, maxAssets);
        deal(address(loanToken), lender, assets);
        collateralize(obligation, borrower, assets.mulDivDown(WAD, lenderOffer.startPrice));
        lenderOffer.assets = assets;

        morphoV2.take(
            assets,
            0,
            0,
            0,
            borrower,
            lenderOffer,
            sig([lenderOffer, otherOffer]),
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
        borrowerOffer.assets = assets;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 0);

        take(assets, 0, 0, 0, lender, borrowerOffer);

        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        uint256 collateral = assets.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.assets = assets;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, assets);
        deal(obligation.collaterals[0].token, callback, collateral);

        morphoV2.take(
            assets,
            0,
            0,
            0,
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer]),
            callback,
            abi.encode(obligation.collaterals[0].token, collateral)
        );
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(obligation.collaterals[0].token, collateral));
    }

    function testSellBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, assets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.assets = assets;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;
        deal(address(loanToken), lenderOffer.callback, assets);
        collateralize(obligation, borrower, assets);

        take(assets, 0, 0, 0, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 assets) public {
        assets = bound(assets, 0, maxAssets);
        (address otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), assets);
        address callback = address(new LendCallback());
        borrowerOffer.assets = assets;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;
        deal(address(loanToken), callback, assets);
        collateralize(obligation, borrower, assets);

        morphoV2.take(
            assets,
            0,
            0,
            0,
            otherLender,
            borrowerOffer,
            sig([borrowerOffer]),
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
