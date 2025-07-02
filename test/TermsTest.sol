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
    address private liquidator = makeAddr("liquidator");
    Term private term;

    bytes32 private id;
    Collateral[] private collaterals;
    Seizure[] private seizures;

    function setUp() public override {
        super.setUp();
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        loanToken = new ERC20("loan", "loan");
        collateralToken = new ERC20("collat", "collat");

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 99);
        deal(address(loanToken), address(borrower), 1);
        deal(address(collateralToken), address(this), 134);
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
        vm.prank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(address(this));
        loanToken.approve(address(terms), type(uint256).max);

        collateralToken.approve(address(terms), type(uint256).max);
        terms.supplyCollateral(term, address(collateralToken), 134, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        Term memory _term = Term(address(loanToken), collaterals, maturity);
        Offer memory offer;
        Signature memory sig;
        vm.expectRevert("maturity");
        terms.take(_term, 100, lender, offer, sig);
    }

    function testLend() public {
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);
        terms.take(term, 100, lender, borrowOffer, borrowSig);

        assertEq(terms.bondSharesOf(lender, id), 100, "lender bond shares");
        assertEq(terms.debtOf(borrower, id), 100, "borrower debt");

        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
    }

    function testBorrow() public {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        terms.take(term, 100, borrower, lendOffer, lendSig);

        assertEq(terms.bondSharesOf(lender, id), 100, "bond shares");
        assertEq(terms.debtOf(borrower, id), 100, "lender debt");

        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
    }

    function testMatch() public {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        terms.take(term, 100, address(this), borrowOffer, borrowSig);
        terms.take(term, 100, address(this), lendOffer, lendSig);

        assertEq(terms.bondSharesOf(address(this), id), 0, "bond shares");
        assertEq(terms.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 100, "balance");
    }

    function testRepay() public {
        testLend();

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

        assertEq(terms.bondSharesOf(lender, id), 0);
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
        testLend();

        deal(address(loanToken), address(liquidator), 1000);
        Oracle(collaterals[0].oracle).setPrice(0.75e36);

        vm.prank(liquidator);
        Seizure[] memory ret = terms.liquidate(term, seizures, borrower, hex"");
        assertEq(terms.debtOf(borrower, id), 0);
        assertEq(ret[0].repaidAmount, 87);
        assertEq(terms.withdrawable(id), 87);
        assertEq(terms.bondOf(lender, id), 87);
        assertEq(terms.totalAssets(id), 87);
    }

    function testConsumed() public {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);

        terms.take(term, 100, borrower, lendOffer, lendSig);

        vm.expectRevert("consumed");
        terms.take(term, 100, borrower, lendOffer, lendSig);
    }

    function testTakeLendOfferCollateralMissing() public {
        collaterals[0].token = address(0);

        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, borrower, lendOffer, lendSig);
    }

    function testTakeLendOfferLLTVMismatch() public {
        collaterals[0].lltv = 0.5e18;

        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, borrower, lendOffer, lendSig);
    }

    function testTakeLendOfferOraclesMismatch() public {
        collaterals[0].oracle = address(0);

        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory lendSig = _signOffer(lendOffer, lenderSK);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, borrower, lendOffer, lendSig);
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        collaterals[0].token = address(0);

        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, 100, lender, borrowOffer, borrowSig);
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        collaterals[0].lltv = 0.99e18;

        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        vm.expectRevert("LLTVs do not match");
        terms.take(term, 100, lender, borrowOffer, borrowSig);
    }

    function testTakeBorrowOfferOraclesMismatch() public {
        collaterals[0].oracle = address(0);

        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 99
        });
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        vm.expectRevert("Oracles do not match");
        terms.take(term, 100, lender, borrowOffer, borrowSig);
    }
}
