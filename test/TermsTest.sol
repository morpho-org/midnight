// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TermsTest is BaseTest {
    ERC20 private loanToken;
    ERC20 private collateralToken;
    ERC20 private secondCollateralToken;
    Oracle private oracle;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    address private liquidator = makeAddr("liquidator");
    Term private term;
    Offer private lendOffer;
    Offer private borrowOffer;

    bytes32 private id;
    Collateral[] private collaterals;
    Seizure[] private seizures;

    function setUp() public override {
        super.setUp();
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        loanToken = new ERC20("loan", "loan");
        collateralToken = new ERC20("collat", "collat");
        secondCollateralToken = new ERC20("collat2", "collat2");

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 100);
        deal(address(collateralToken), address(this), 135);
        deal(address(collateralToken), address(this), type(uint256).max);
        oracle = new Oracle();

        collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(secondCollateralToken), lltv: 0.75e18, oracle: address(oracle)});

        seizures = new Seizure[](2);
        seizures[0] = Seizure({repaidBonds: 0, seizedAssets: 135});
        seizures[1] = Seizure({repaidBonds: 0, seizedAssets: 0});

        term = Term(address(loanToken), collaterals, block.timestamp + 100);
        id = keccak256(abi.encode(term));

        lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            rate: 0.01e18 / 100,
            nonce: 0
        });

        borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            rate: 0.01e18 / 100,
            nonce: 0
        });

        vm.startPrank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        terms.setMatching(address(matching), true);
        vm.stopPrank();

        vm.startPrank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        terms.setMatching(address(matching), true);
        vm.stopPrank();

        vm.startPrank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
        vm.stopPrank();

        loanToken.approve(address(terms), type(uint256).max);
        terms.setMatching(address(matching), true);

        collateralToken.approve(address(terms), type(uint256).max);
        terms.supplyCollateral(term, address(collateralToken), 135, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        Term memory _term = Term(address(loanToken), collaterals, maturity);
        Offer memory offer;
        Signature memory sig;
        vm.expectRevert("maturity");
        terms.take(_term, 100, lender, true, address(matching), abi.encode(offer, sig));
    }

    function testLend() public {
        terms.take(term, 100, lender, true, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK)));

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "borrower debt");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(matching.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testBorrow() public {
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        assertEq(terms.bondSharesOf(lender, id), 101, "bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "lender debt");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(matching.consumed(lender, 0), 100, "lender nonce");
    }

    function testMatch() public {
        terms.take(
            term, 100, address(this), true, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK))
        );
        terms.take(term, 100, address(this), false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        assertEq(terms.bondSharesOf(address(this), id), 0, "bond shares");
        assertEq(terms.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 100, "balance");
        assertEq(matching.consumed(lender, 0), 100, "lender nonce");
        assertEq(matching.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testRepay() public {
        testLend();

        vm.warp(block.timestamp + 99);

        deal(address(loanToken), address(borrower), 101);

        vm.prank(borrower);
        terms.repayDebt(term, 101, borrower);

        assertEq(terms.debtOf(borrower, id), 0);
        assertEq(terms.withdrawable(id), 101);
        assertEq(loanToken.balanceOf(address(terms)), 101);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdraw() public {
        testRepay();

        vm.prank(lender);
        terms.withdrawBond(term, 101, 0, lender);

        assertEq(terms.bondSharesOf(lender, id), 0);
        assertEq(terms.withdrawable(id), 0);
        assertEq(loanToken.balanceOf(address(terms)), 0);
        assertEq(loanToken.balanceOf(lender), 101);
    }

    function testWithdrawCollateral() public {
        testRepay();

        vm.prank(borrower);
        terms.withdrawCollateral(term, address(collateralToken), 135, borrower);

        assertEq(terms.collateralOf(borrower, id, address(collateralToken)), 0);
        assertEq(collateralToken.balanceOf(address(terms)), 0);
        assertEq(collateralToken.balanceOf(borrower), 135);
    }

    function testBadDebt() public {
        testLend();

        deal(address(loanToken), address(liquidator), 1000);
        Oracle(collaterals[0].oracle).setPrice(0.75e36);

        vm.prank(liquidator);
        Seizure[] memory ret = terms.liquidate(term, seizures, borrower, hex"");
        assertEq(terms.debtOf(borrower, id), 0);
        assertEq(ret[0].repaidBonds, 88);
        assertEq(terms.withdrawable(id), 88);
        assertEq(terms.bondOf(lender, id), 88);
        assertEq(terms.totalBonds(id), 88);
    }

    function testConsumed() public {
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        vm.expectRevert("consumed");
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));
    }

    function testPartialFill() public {
        terms.take(term, 50, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        assertEq(matching.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        terms.take(term, 51, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        terms.take(term, 50, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        assertEq(matching.consumed(lender, 0), 100);
    }

    function testOCO() public {
        Offer memory lendOffer2 = lendOffer;
        lendOffer2.maturity = block.timestamp + 200;
        Term memory term2 = term;
        term2.maturity = block.timestamp + 200;

        terms.take(term, 70, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));

        vm.expectRevert("consumed");
        terms.take(term2, 31, borrower, false, address(matching), abi.encode(lendOffer2, sig(lendOffer2, lenderSK)));

        terms.supplyCollateral(term2, address(collateralToken), 134, borrower);

        terms.take(term2, 30, borrower, false, address(matching), abi.encode(lendOffer2, sig(lendOffer2, lenderSK)));
        assertEq(matching.consumed(lender, 0), 100);
    }

    function testTakeLendOfferCollateralMissing() public {
        lendOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));
    }

    function testTakeLendOfferLLTVMismatch() public {
        lendOffer.collaterals[0].lltv = 0.5e18;

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));
    }

    function testTakeLendOfferOraclesMismatch() public {
        lendOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, borrower, false, address(matching), abi.encode(lendOffer, sig(lendOffer, lenderSK)));
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        borrowOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, lender, true, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK)));
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        borrowOffer.collaterals[0].lltv = 0.99e18;

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, lender, true, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK)));
    }

    function testTakeBorrowOfferOraclesMismatch() public {
        borrowOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, lender, true, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK)));
    }
}
