// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    Term internal term;
    bytes32 internal id;
    Offer internal buyOffer;
    MatchData internal buyMatchData;
    Offer internal sellOffer;
    MatchData internal sellMatchData;
    Order internal buyOrder;
    Order internal sellOrder;

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

        buyMatchData.loanToken = address(loanToken);
        for (uint256 i = 0; i < collaterals.length; i++) {
            buyMatchData.collaterals.push(collaterals[i]);
        }
        buyMatchData.maturity = block.timestamp + 100;
        buyMatchData.rate = 0.01e18 / 100;

        buyOffer.buying = true;
        buyOffer.asBorrower = false;
        buyOffer.owner = lender;
        buyOffer.assets = 100;
        buyOffer.matching = address(matching);
        buyOffer.matchData = abi.encode(buyMatchData);
        buyOffer.hook = address(0);
        buyOffer.hookData = hex"";
        buyOffer.nonce = 0;
        buyOffer.start = block.timestamp;
        buyOffer.expiry = block.timestamp + 200;

        sellMatchData.loanToken = address(loanToken);
        for (uint256 i = 0; i < collaterals.length; i++) {
            sellMatchData.collaterals.push(collaterals[i]);
        }
        sellMatchData.maturity = block.timestamp + 100;
        sellMatchData.rate = 0.01e18 / 100;

        sellOffer.buying = false;
        sellOffer.asBorrower = true;
        sellOffer.owner = borrower;
        sellOffer.assets = 100;
        sellOffer.matching = address(matching);
        sellOffer.matchData = abi.encode(sellMatchData);
        sellOffer.hook = address(0);
        sellOffer.hookData = hex"";
        sellOffer.nonce = 0;
        sellOffer.start = block.timestamp;
        sellOffer.expiry = block.timestamp + 200;

        terms.supplyCollateral(term, address(collateralToken1), 135, borrower);

        buyOrder.owner = lender;
        buyOrder.assets = 100;
        buyOrder.bonds = 101;
        buyOrder.hook = address(0);
        buyOrder.hookData = hex"";

        vm.prank(lender);
        terms.setAuthorized(address(this), true);

        sellOrder.owner = borrower;
        sellOrder.assets = 100;
        sellOrder.bonds = 101;
        sellOrder.hook = address(0);
        sellOrder.hookData = hex"";

        vm.prank(borrower);
        terms.setAuthorized(address(this), true);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        term.maturity = maturity;
        Offer memory offer;
        offer.expiry = block.timestamp;
        Signature memory sig;
        vm.expectRevert("bond maturity");
        terms.take(term, buyOrder, offer);
    }

    function testLend() public {
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "borrower debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(terms.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testBorrow() public {
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.bondSharesOf(lender, id), 101, "bond shares");
        assertEq(terms.debtOf(borrower, id), 101, "lender debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(terms.consumed(lender, 0), 100, "lender nonce");
    }

    function testWithdrawSecondaryWithLender() public {
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);

        address otherLender = makeAddr("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(terms), 100);
        deal(address(loanToken), otherLender, 100);
        buyOffer.owner = otherLender;
        vm.prank(otherLender);
        terms.setRatified(buyOffer, true);
        sellOrder.owner = lender;
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(otherLender, id), 101, "other lender bond shares");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(terms.consumed(otherLender, 0), 100, "other lender nonce");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), 0, "other lender balance");
    }

    function testWithdrawSecondaryWithBorrower() public {
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);
        buyOffer.asBorrower = true;
        buyOffer.owner = borrower;
        buyOffer.nonce = 1;
        sellOrder.owner = lender;
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.totalBonds(id), 0, "total bonds");
        assertEq(terms.totalShares(id), 0, "total shares");
        assertEq(terms.consumed(borrower, 1), 100, "borrower nonce");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
    }

    function testRepaySecondaryWithBorrower() public {
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        address otherBorrower = makeAddr("otherBorrower");
        vm.prank(otherBorrower);
        collateralToken1.approve(address(terms), 135);
        deal(address(collateralToken1), otherBorrower, 135);
        terms.supplyCollateral(term, address(collateralToken1), 135, otherBorrower);
        sellOffer.owner = otherBorrower;
        buyOrder.owner = borrower;
        vm.prank(otherBorrower);
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);

        assertEq(terms.bondSharesOf(lender, id), 101, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.bondSharesOf(otherBorrower, id), 0, "other borrower bond shares");
        assertEq(terms.debtOf(borrower, id), 0, "borrower debt");
        assertEq(terms.debtOf(otherBorrower, id), 101, "other borrower debt");
        assertEq(terms.totalBonds(id), 101, "total bonds");
        assertEq(terms.totalShares(id), 101, "total shares");
        assertEq(terms.consumed(otherBorrower, 0), 100, "other borrower nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), 100, "other borrower balance");
    }

    function testRepaySecondaryWithLender() public {
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        sellOffer.asBorrower = false;
        sellOffer.owner = lender;
        sellOffer.nonce = 1;
        buyOrder.owner = borrower;
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);

        assertEq(terms.bondSharesOf(lender, id), 0, "lender bond shares");
        assertEq(terms.bondSharesOf(borrower, id), 0, "borrower bond shares");
        assertEq(terms.debtOf(borrower, id), 0, "borrower debt");
        assertEq(terms.debtOf(lender, id), 0, "lender debt");
        assertEq(terms.totalBonds(id), 0, "total bonds");
        assertEq(terms.totalShares(id), 0, "total shares");
        assertEq(terms.consumed(lender, 1), 100, "lender nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
    }

    function testMatch() public {
        buyOrder.owner = address(this);
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);

        sellOrder.owner = address(this);
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.bondSharesOf(address(this), id), 0, "bond shares");
        assertEq(terms.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 100, "balance");
        assertEq(terms.consumed(lender, 0), 100, "lender nonce");
        assertEq(terms.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testConsumed() public {
        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        sellOrder.assets = 1;
        sellOrder.bonds = 2;

        vm.expectRevert("consumed");
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakePartialFill() public {
        buyMatchData.rate = 0; // to simplify inputs
        buyOffer.matchData = abi.encode(buyMatchData);
        sellOrder.assets = 50;
        sellOrder.bonds = 50;

        terms.setRatified(buyOffer, true);
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        sellOrder.assets = 51;
        sellOrder.bonds = 51;
        terms.take(term, sellOrder, buyOffer);

        sellOrder.assets = 50;
        sellOrder.bonds = 50;
        terms.take(term, sellOrder, buyOffer);

        assertEq(terms.consumed(lender, 0), 100);
    }

    function testTakeOCO() public {
        buyMatchData.rate = 0; // to simplify inputs
        buyOffer.matchData = abi.encode(buyMatchData);

        Offer memory buyOffer1 = buyOffer;

        buyMatchData.maturity = block.timestamp + 200;
        buyOffer.matchData = abi.encode(buyMatchData);
        buyOffer.expiry = block.timestamp + 200;
        Offer memory buyOffer2 = buyOffer;

        Term memory term2 = term;
        term2.maturity = block.timestamp + 200;

        terms.setRatified(buyOffer1, true);
        sellOrder.assets = 70;
        sellOrder.bonds = 70;

        terms.take(term, sellOrder, buyOffer1);

        terms.setRatified(buyOffer2, true);
        sellOrder.assets = 31;
        sellOrder.bonds = 31;

        vm.expectRevert("consumed");
        terms.take(term2, sellOrder, buyOffer2);

        terms.supplyCollateral(term2, address(collateralToken1), 134, borrower);

        sellOrder.assets = 30;
        sellOrder.bonds = 30;
        terms.take(term2, sellOrder, buyOffer2);
        assertEq(terms.consumed(lender, 0), 100);
    }

    function testTakeLendBorrowHook() public {
        address otherBorrower = makeAddr("otherBorrower");
        sellOffer.hook = address(new BorrowHook());
        sellOffer.hookData = abi.encode(address(collateralToken1), 135);
        sellOffer.owner = address(otherBorrower);
        deal(address(collateralToken1), sellOffer.hook, 135);
        assertEq(terms.collateralOf(otherBorrower, id, address(collateralToken1)), 0);

        vm.prank(otherBorrower);
        terms.setRatified(sellOffer, true);
        terms.take(term, buyOrder, sellOffer);
        assertEq(terms.collateralOf(otherBorrower, id, address(collateralToken1)), 135);
        assertEq(BorrowHook(sellOffer.hook).recordedData(), sellOffer.hookData);
    }

    function testTakeBorrowBorrowCallback() public {
        address otherBorrower = makeAddr("otherBorrower");

        sellOrder.owner = otherBorrower;
        sellOrder.hook = address(new BorrowHook());
        sellOrder.hookData = abi.encode(address(collateralToken1), 135);
        deal(address(collateralToken1), sellOrder.hook, 135);
        assertEq(terms.collateralOf(otherBorrower, id, address(collateralToken1)), 0);

        terms.setRatified(buyOffer, true);

        vm.prank(otherBorrower);
        terms.take(term, sellOrder, buyOffer);
        assertEq(terms.collateralOf(otherBorrower, id, address(collateralToken1)), 135);
        assertEq(BorrowHook(sellOrder.hook).recordedData(), abi.encode(address(collateralToken1), 135));
    }

    function testTakeBorrowLendCallback() public {
        address otherLender = makeAddr("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(terms), 100);
        buyOffer.hook = address(new LendHook());
        buyOffer.hookData = abi.encode(address(loanToken), 100);
        buyOffer.owner = address(otherLender);
        deal(address(loanToken), buyOffer.hook, 100);

        vm.prank(otherLender);
        terms.setRatified(buyOffer, true);

        terms.take(term, sellOrder, buyOffer);
        assertEq(LendHook(buyOffer.hook).recordedData(), buyOffer.hookData);
    }

    function testTakeLendLendCallback() public {
        address otherLender = makeAddr("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(terms), 100);
        buyOrder.hook = address(new LendHook());
        buyOrder.hookData = abi.encode(address(loanToken), 100);
        buyOrder.owner = address(otherLender);
        deal(address(loanToken), buyOrder.hook, 100);

        terms.setRatified(sellOffer, true);

        vm.prank(otherLender);
        terms.take(term, buyOrder, sellOffer);
        assertEq(LendHook(buyOrder.hook).recordedData(), abi.encode(address(loanToken), 100));
    }

    function testTakeMaturityPassed() public {
        vm.warp(block.timestamp + 101);
        terms.setRatified(sellOffer, true);
        vm.expectRevert("bond maturity");
        terms.take(term, buyOrder, sellOffer);
    }

    function testTakeLendOfferCollateralMissing() public {
        buyMatchData.collaterals[0].token = address(0);
        buyOffer.matchData = abi.encode(buyMatchData);
        terms.setRatified(buyOffer, true);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakeLendOfferLLTVMismatch() public {
        buyMatchData.collaterals[0].lltv = 0.5e18;
        buyOffer.matchData = abi.encode(buyMatchData);
        terms.setRatified(buyOffer, true);

        vm.expectRevert("LLTVs do not match");
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakeLendOfferOraclesMismatch() public {
        buyMatchData.collaterals[0].oracle = address(0);
        buyOffer.matchData = abi.encode(buyMatchData);
        terms.setRatified(buyOffer, true);

        vm.expectRevert("Oracles do not match");
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        sellMatchData.collaterals[0].token = address(0);
        sellOffer.matchData = abi.encode(sellMatchData);
        terms.setRatified(sellOffer, true);

        vm.expectRevert(stdError.indexOOBError);
        terms.take(term, buyOrder, sellOffer);
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        sellMatchData.collaterals[0].lltv = 0.99e18;
        sellOffer.matchData = abi.encode(sellMatchData);
        terms.setRatified(sellOffer, true);

        vm.expectRevert("LLTVs do not match");
        terms.take(term, buyOrder, sellOffer);
    }

    function testTakeBorrowOfferOraclesMismatch() public {
        sellMatchData.collaterals[0].oracle = address(0);
        sellOffer.matchData = abi.encode(sellMatchData);
        terms.setRatified(sellOffer, true);

        vm.expectRevert("Oracles do not match");
        terms.take(term, buyOrder, sellOffer);
    }

    function testTakeSellerMakerNotHealthyOffer() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        terms.setRatified(sellOffer, true);
        vm.expectRevert("Seller is unhealthy");
        terms.take(term, buyOrder, sellOffer);
    }

    function testTakeSellerTakerNotHealthy() public {
        terms.withdrawCollateral(term, address(collateralToken1), 1, borrower);
        terms.setRatified(buyOffer, true);
        vm.expectRevert("Seller is unhealthy");
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakeOfferWrongLoanToken(address _loanToken) public {
        vm.assume(_loanToken != address(loanToken));

        buyMatchData.loanToken = _loanToken;
        buyOffer.matchData = abi.encode(buyMatchData);
        buyOffer.expiry = block.timestamp + 200;
        terms.setRatified(buyOffer, true);

        vm.expectRevert("Loan tokens do not match");
        terms.take(term, sellOrder, buyOffer);
    }

    function testTakeOfferWrongMaturity(uint256 _maturity) public {
        vm.assume(_maturity != term.maturity);

        buyMatchData.maturity = _maturity;
        buyOffer.matchData = abi.encode(buyMatchData);
        buyOffer.expiry = block.timestamp + 200;
        terms.setRatified(buyOffer, true);

        vm.expectRevert("Maturities do not match");
        terms.take(term, sellOrder, buyOffer);
    }
}

contract BorrowHook is ISeller {
    bytes public recordedData;

    function checkRatified(Offer memory offer, bool isRatified, bytes memory data) external returns (bytes32) {
        recordedData = data;
        return RATIFICATION_RESPONSE;
    }

    function onSell(Term memory term, uint256 assets, uint256 bonds, address seller, bytes memory data) external {
        recordedData = data;
        (address collateralToken, uint256 amount) = abi.decode(data, (address, uint256));
        ERC20(collateralToken).approve(msg.sender, type(uint256).max);
        Terms(msg.sender).supplyCollateral(
            term, collateralToken, ERC20(collateralToken).balanceOf(address(this)), seller
        );
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}

contract LendHook is IBuyer {
    bytes public recordedData;

    function onBuy(Term memory term, uint256 assets, uint256 bonds, address buyer, bytes memory data) external {
        recordedData = data;
        ERC20(term.loanToken).transfer(buyer, assets);
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}
