// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    Term internal term;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;

    function setUp() public override {
        super.setUp();

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 100);
        deal(address(collateralToken1), address(this), 135);
        deal(address(collateralToken1), address(this), type(uint256).max);

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});
        collaterals = sortCollaterals(collaterals);

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        term.loanToken = address(loanToken);
        term.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            term.collaterals.push(collaterals[i]);
        }

        id = keccak256(abi.encode(term));

        lendOffer.buy = true;
        lendOffer.offering = lender;
        lendOffer.assets = 100;
        lendOffer.loanToken = address(loanToken);
        lendOffer.maturity = block.timestamp + 100;
        lendOffer.rate = 0.01e18 / 100;
        lendOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            lendOffer.collaterals.push(collaterals[i]);
        }

        borrowOffer.buy = false;
        borrowOffer.offering = borrower;
        borrowOffer.assets = 100;
        borrowOffer.loanToken = address(loanToken);
        borrowOffer.maturity = block.timestamp + 100;
        borrowOffer.rate = 0.01e18 / 100;
        borrowOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            borrowOffer.collaterals.push(collaterals[i]);
        }

        terms.supplyCollateral(term, address(collateralToken1), 135, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        term.maturity = maturity;
        Offer memory offer;
        Signature memory sig;
        vm.expectRevert("maturity");
        terms.take(term, 100, 0, 101, lender, address(matching), abi.encode(offer, sig), borrower, address(0), hex"");
    }

    function testLend() public {
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "borrower debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(matching.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testBorrow() public {
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        assertEq(terms.bondSharesOf(lender, id), 101, "bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "lender debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(matching.consumed(lender, 0), 100, "lender nonce");
    }

    function testWithdrawSecondaryWithLender() public {
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );

        (address otherLender, uint256 otherLenderSK) = makeAddrAndKey("otherLender");
        vm.startPrank(otherLender);
        terms.setHook(address(matching), true);
        loanToken.approve(address(terms), 100);
        vm.stopPrank();
        deal(address(loanToken), otherLender, 100);
        lendOffer.offering = otherLender;
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            otherLender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, otherLenderSK)),
            lender,
            address(0),
            hex""
        );

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(otherLender, id), 101, "other lender bond shares");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(matching.consumed(otherLender, 0), 100, "other lender nonce");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), 0, "other lender balance");
    }

    function testWithdrawSecondaryWithBorrower() public {
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
        lendOffer.offering = borrower;
        lendOffer.nonce = 1;
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            borrower,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, borrowerSK)),
            lender,
            address(0),
            hex""
        );

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.totalBonds(id), 0, "total bonds");
        assertEq(terms.totalShares(id), 0, "total shares");
        assertEq(matching.consumed(borrower, 1), 100, "borrower nonce");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
    }

    function testRepaySecondaryWithBorrower() public {
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        (address otherBorrower, uint256 otherBorrowerSK) = makeAddrAndKey("otherBorrower");
        vm.startPrank(otherBorrower);
        terms.setHook(address(matching), true);
        collateralToken1.approve(address(terms), 135);
        vm.stopPrank();

        deal(address(collateralToken1), otherBorrower, 135);
        terms.supplyCollateral(term, address(collateralToken1), 135, otherBorrower);
        borrowOffer.offering = otherBorrower;
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            borrower,
            address(0),
            hex"",
            otherBorrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, otherBorrowerSK))
        );

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.bondSharesOf(otherBorrower, id), 0, "other borrower bond shares");
        assertEq(terms.debtOf(borrower, id), 0, "borrower debt");
        assertEq(terms.debtOf(otherBorrower, id), 101, "other borrower debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(matching.consumed(otherBorrower, 0), 100, "other borrower nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), 100, "other borrower balance");
    }

    function testRepaySecondaryWithLender() public {
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        borrowOffer.offering = lender;
        borrowOffer.nonce = 1;
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            borrower,
            address(0),
            hex"",
            lender,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, lenderSK))
        );

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.debtOf(borrower, id), 0, "borrower debt");
        assertEq(terms.debtOf(lender, id), 0, "lender debt");
        assertEq(terms.totalBonds(id), 0, "total bonds");
        assertEq(terms.totalShares(id), 0, "total shares");
        assertEq(matching.consumed(lender, 1), 100, "lender nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
    }

    function testMatch() public {
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );

        assertEq(terms.bondSharesOf(address(this), id), 0, "bond shares");
        assertEq(terms.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 100, "balance");
        assertEq(matching.consumed(lender, 0), 100, "lender nonce");
        assertEq(matching.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testConsumed() public {
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        vm.expectRevert("consumed");
        vm.prank(borrower);
        terms.take(
            term,
            1,
            0,
            2,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakePartialFill() public {
        lendOffer.rate = 0; // to simplify inputs

        vm.prank(borrower);
        terms.take(
            term,
            50,
            0,
            50,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        assertEq(matching.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        vm.prank(borrower);
        terms.take(
            term,
            51,
            0,
            51,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        vm.prank(borrower);
        terms.take(
            term,
            50,
            0,
            50,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        assertEq(matching.consumed(lender, 0), 100);
    }

    function testTakeOCO() public {
        lendOffer.rate = 0; // to simplify inputs
        Offer memory lendOffer2 = lendOffer;
        lendOffer2.maturity = block.timestamp + 200;
        Term memory term2 = term;
        term2.maturity = block.timestamp + 200;
        terms.supplyCollateral(term2, address(collateralToken1), 135, borrower);

        vm.prank(borrower);
        terms.take(
            term,
            70,
            0,
            70,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        vm.expectRevert("consumed");
        vm.prank(borrower);
        terms.take(
            term2,
            31,
            0,
            31,
            lender,
            address(matching),
            abi.encode(lendOffer2, sig(lendOffer2, lenderSK)),
            borrower,
            address(0),
            hex""
        );

        vm.prank(borrower);
        terms.take(
            term2,
            30,
            0,
            30,
            lender,
            address(matching),
            abi.encode(lendOffer2, sig(lendOffer2, lenderSK)),
            borrower,
            address(0),
            hex""
        );
        assertEq(matching.consumed(lender, 0), 100);
    }

    function testTakeMaturityPassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert("maturity");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeLendOfferCollateralMissing() public {
        lendOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeLendOfferLLTVMismatch() public {
        lendOffer.collaterals[0].lltv = 0.5e18;

        vm.expectRevert("LLTVs do not match");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeLendOfferOraclesMismatch() public {
        lendOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        borrowOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        borrowOffer.collaterals[0].lltv = 0.99e18;

        vm.expectRevert("LLTVs do not match");
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
    }

    function testTakeBorrowOfferOraclesMismatch() public {
        borrowOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
    }

    function testTakeSellerMakerNotHealthyMaker() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        vm.prank(lender);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(0),
            hex"",
            borrower,
            address(matching),
            abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
    }

    function testTakeSellerTakerNotHealthy() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeOfferWrongLoanToken(address _loanToken) public {
        vm.assume(_loanToken != address(loanToken));
        lendOffer.loanToken = _loanToken;
        vm.expectRevert("Loan tokens do not match");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeOfferWrongMaturity(uint256 _maturity) public {
        vm.assume(_maturity != term.maturity);
        lendOffer.maturity = _maturity;
        vm.expectRevert("Maturities do not match");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(lendOffer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeWrongSignature(Offer memory _offer) public {
        vm.assume(keccak256(abi.encode(_offer)) != keccak256(abi.encode(lendOffer)));
        vm.expectRevert("Invalid signature");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, sig(_offer, lenderSK)),
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert("Invalid signature");
        vm.prank(borrower);
        terms.take(
            term,
            100,
            0,
            101,
            lender,
            address(matching),
            abi.encode(lendOffer, Signature(0, 0, 0)),
            borrower,
            address(0),
            hex""
        );
    }
}
