// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TermsTest is BaseTest {
    ERC20 private loanToken;
    ERC20 private collateralToken;
    Oracle private oracle;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    address private liquidator;
    Term private term;

    bytes32 private id;
    Collateral[] private collaterals;
    Seizure[] private seizures;

    function setUp() public override {
        super.setUp();
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");
        liquidator = makeAddr("liquidator");

        loanToken = new ERC20("loan", "loan", 1 ether);
        loanToken.transfer(lender, 99);
        loanToken.transfer(borrower, 1);
        collateralToken = new ERC20("collat", "collat", 1 ether);
        oracle = new Oracle();

        collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken), lltv: 0.75e18, oracle: address(oracle)});

        seizures = new Seizure[](1);
        seizures[0] = Seizure({repaidAmount: 0, seizedAssets: 134});

        term = Term(address(loanToken), collaterals, block.timestamp + 100);
        id = keccak256(abi.encode(term));

        vm.prank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        collateralToken.approve(address(terms), type(uint256).max);
        terms.supplyCollateral(term, address(collateralToken), 134, borrower);
        vm.prank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
    }

    function testMint() public {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });

        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        terms.MATCH(lendOffer, lendSig, borrowOffer, borrowSig);

        assertEq(terms.bondOf(lender, id), 100);
        assertEq(terms.debtOf(borrower, id), 100);

        assertEq(loanToken.balanceOf(borrower), 100);
        assertEq(loanToken.balanceOf(lender), 0);
    }

    function testRepay() public {
        testMint();

        vm.warp(block.timestamp + 99);

        vm.prank(borrower);
        terms.repayDebt(term, 100, borrower);

        assertEq(terms.debtOf(borrower, id), 0);
        assertEq(terms.withdrawable(id), 100);

        assertEq(loanToken.balanceOf(address(terms)), 100);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdraw() public {
        testRepay();

        vm.prank(lender);
        terms.withdrawBond(term, 100, 0, lender);

        assertEq(terms.bondOf(lender, id), 0);
        assertEq(terms.withdrawable(id), 0);

        assertEq(loanToken.balanceOf(address(terms)), 0);
        assertEq(loanToken.balanceOf(lender), 100);
    }

    function testWithdrawCollateral() public {
        testRepay();

        vm.prank(borrower);
        terms.withdrawCollateral(term, address(collateralToken), 134, borrower);

        assertEq(terms.collateralOf(borrower, id, address(collateralToken)), 0);

        assertEq(collateralToken.balanceOf(address(terms)), 0);
        assertEq(collateralToken.balanceOf(borrower), 134);
    }

    function testBadDebt() public {
        testMint();

        loanToken.transfer(liquidator, 1000);
        vm.prank(liquidator);
        terms.mintAtPar(term, 87, liquidator);
        Oracle(collaterals[0].oracle).setPrice(0.75e36);

        vm.prank(liquidator);
        Seizure[] memory ret = terms.liquidate(term, seizures, borrower, hex"");
        assertEq(terms.debtOf(borrower, id), 0);
        assertEq(ret[0].repaidAmount, 87);
        assertEq(terms.withdrawable(id), 87);
        assertEq(terms.bondOf(lender, id), 87);
        assertEq(terms.bondOf(liquidator, id), 0);

        assertEq(terms.totalAssets(id), 87);
    }

    function testFuzzMintAtPar(uint256 amount) public {
        uint256 MAX_AMOUNT = 1 ether - 100;
        amount = bound(amount, 1, MAX_AMOUNT);
        loanToken.transfer(liquidator, MAX_AMOUNT);
        assertEq(terms.bondOf(liquidator, id), 0);
        vm.prank(liquidator);
        terms.mintAtPar(term, amount, liquidator);
        assertEq(loanToken.balanceOf(liquidator), MAX_AMOUNT - amount);
        assertEq(terms.bondOf(liquidator, id), amount);
    }
}
