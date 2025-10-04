// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;

    function setUp() public override {
        super.setUp();

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 100);
        deal(address(collateralToken1), address(this), type(uint256).max);

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});
        collaterals = sortCollaterals(collaterals);

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            obligation.collaterals.push(collaterals[i]);
        }

        id = keccak256(abi.encode(obligation));

        lendOffer.buy = true;
        lendOffer.maker = lender;
        lendOffer.assets = 100;
        lendOffer.loanToken = address(loanToken);
        lendOffer.maturity = block.timestamp + 100;
        lendOffer.start = block.timestamp;
        lendOffer.expiry = block.timestamp + 200;
        lendOffer.startPrice = 0.99 ether;
        lendOffer.expiryPrice = 0.99 ether;
        lendOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            lendOffer.collaterals.push(collaterals[i]);
        }

        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = 100;
        borrowOffer.loanToken = address(loanToken);
        borrowOffer.maturity = block.timestamp + 100;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 0.99 ether;
        borrowOffer.expiryPrice = 0.99 ether;
        borrowOffer.nonce = 0;

        for (uint256 i = 0; i < collaterals.length; i++) {
            borrowOffer.collaterals.push(collaterals[i]);
        }

        morphoV2.supplyCollateral(obligation, address(collateralToken1), 135, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        obligation.maturity = maturity;
        Offer memory offer;
        offer.expiry = block.timestamp;
        Signature memory sig;
        vm.expectRevert("maturity");
        morphoV2.take(obligation, 100, 0, lender, offer, sig, address(0), hex"");
    }

    function testLend() public {
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 101, "borrower debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testBorrow() public {
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 101, "obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 101, "lender debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(lender, 0), 100, "lender nonce");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), 100, "lender nonce");
    }

    function testWithdrawSecondaryWithLender() public {
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        (address otherLender, uint256 otherLenderSK) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        deal(address(loanToken), otherLender, 100);
        lendOffer.maker = otherLender;
        morphoV2.take(obligation, 0, 101, lender, lendOffer, sig(lendOffer, otherLenderSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(otherLender, id), 101, "other lender obligation shares");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(otherLender, 0), 99, "other lender nonce");
        assertEq(loanToken.balanceOf(lender), 99, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), 1, "other lender balance");
    }

    function testWithdrawSecondaryWithBorrower() public {
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
        lendOffer.maker = borrower;
        lendOffer.nonce = 1;
        morphoV2.take(obligation, 0, 101, lender, lendOffer, sig(lendOffer, borrowerSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.totalUnits(id), 0, "total obligations");
        assertEq(morphoV2.totalShares(id), 0, "total shares");
        assertEq(morphoV2.consumed(borrower, 1), 99, "borrower nonce");
        assertEq(loanToken.balanceOf(lender), 99, "lender balance");
        assertEq(loanToken.balanceOf(borrower), 1, "borrower balance");
    }

    function testRepaySecondaryWithBorrower() public {
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        (address otherBorrower, uint256 otherBorrowerSK) = makeAddrAndKey("otherBorrower");
        vm.prank(otherBorrower);
        collateralToken1.approve(address(morphoV2), 135);
        deal(address(collateralToken1), otherBorrower, 135);
        morphoV2.supplyCollateral(obligation, address(collateralToken1), 135, otherBorrower);
        borrowOffer.maker = otherBorrower;
        morphoV2.take(obligation, 100, 0, borrower, borrowOffer, sig(borrowOffer, otherBorrowerSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.sharesOf(otherBorrower, id), 0, "other borrower obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 0, "borrower debt");
        assertEq(morphoV2.debtOf(otherBorrower, id), 101, "other borrower debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(otherBorrower, 0), 100, "other borrower nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), 100, "other borrower balance");
    }

    function testRepaySecondaryWithLender() public {
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        borrowOffer.maker = lender;
        borrowOffer.nonce = 1;
        morphoV2.take(obligation, 100, 0, borrower, borrowOffer, sig(borrowOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 0, "borrower debt");
        assertEq(morphoV2.debtOf(lender, id), 0, "lender debt");
        assertEq(morphoV2.totalUnits(id), 0, "total obligations");
        assertEq(morphoV2.totalShares(id), 0, "total shares");
        assertEq(morphoV2.consumed(lender, 1), 100, "lender nonce");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
    }

    function testMatch() public {
        morphoV2.take(obligation, 100, 0, address(this), borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
        morphoV2.take(obligation, 0, 101, address(this), lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(address(this), id), 0, "obligation shares");
        assertEq(morphoV2.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 99, "balance");
        assertEq(morphoV2.consumed(lender, 0), 99, "lender nonce");
        assertEq(morphoV2.consumed(borrower, 0), 100, "borrower nonce");
    }

    function testConsumed() public {
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        vm.expectRevert("consumed");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakePartialFill() public {
        morphoV2.take(obligation, 50, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        morphoV2.take(obligation, 51, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        morphoV2.take(obligation, 50, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.consumed(lender, 0), 100);
    }

    function testTakeOCO() public {
        Offer memory lendOffer2 = lendOffer;
        lendOffer2.maturity = block.timestamp + 200;
        lendOffer2.expiry = block.timestamp + 200;
        Obligation memory obligation2 = obligation;
        obligation2.maturity = block.timestamp + 200;

        morphoV2.take(obligation, 70, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        vm.expectRevert("consumed");
        morphoV2.take(obligation2, 31, 0, borrower, lendOffer2, sig(lendOffer2, lenderSK), address(0), hex"");

        morphoV2.supplyCollateral(obligation2, address(collateralToken1), 134, borrower);

        morphoV2.take(obligation2, 30, 0, borrower, lendOffer2, sig(lendOffer2, lenderSK), address(0), hex"");
        assertEq(morphoV2.consumed(lender, 0), 100);
    }

    function testTakeLendBorrowCallback() public {
        (address otherBorrower, uint256 otherBorrowerSK) = makeAddrAndKey("otherBorrower");
        borrowOffer.callbackAddress = address(new BorrowCallback());
        borrowOffer.callbackData = abi.encode(address(collateralToken1), 135);
        borrowOffer.maker = address(otherBorrower);
        deal(address(collateralToken1), borrowOffer.callbackAddress, 135);
        assertEq(morphoV2.collateralOf(otherBorrower, id, address(collateralToken1)), 0);

        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, otherBorrowerSK), address(0), hex"");
        assertEq(morphoV2.collateralOf(otherBorrower, id, address(collateralToken1)), 135);
        assertEq(BorrowCallback(borrowOffer.callbackAddress).recordedData(), borrowOffer.callbackData);
    }

    function testTakeBorrowBorrowCallback() public {
        (address otherBorrower,) = makeAddrAndKey("otherBorrower");
        address callbackAddress = address(new BorrowCallback());
        deal(address(collateralToken1), callbackAddress, 135);
        assertEq(morphoV2.collateralOf(otherBorrower, id, address(collateralToken1)), 0);

        vm.prank(otherBorrower);
        morphoV2.take(
            obligation,
            100,
            0,
            otherBorrower,
            lendOffer,
            sig(lendOffer, lenderSK),
            callbackAddress,
            abi.encode(address(collateralToken1), 135)
        );
        assertEq(morphoV2.collateralOf(otherBorrower, id, address(collateralToken1)), 135);
        assertEq(BorrowCallback(callbackAddress).recordedData(), abi.encode(address(collateralToken1), 135));
    }

    function testTakeBorrowLendCallback() public {
        (address otherLender, uint256 otherLenderSK) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        lendOffer.callbackAddress = address(new LendCallback());
        lendOffer.callbackData = abi.encode(address(loanToken), 100);
        lendOffer.maker = address(otherLender);
        deal(address(loanToken), lendOffer.callbackAddress, 100);

        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, otherLenderSK), address(0), hex"");
        assertEq(LendCallback(lendOffer.callbackAddress).recordedData(), lendOffer.callbackData);
    }

    function testTakeLendLendCallback() public {
        (address otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        address callbackAddress = address(new LendCallback());
        deal(address(loanToken), callbackAddress, 100);

        vm.prank(otherLender);
        morphoV2.take(
            obligation,
            100,
            0,
            otherLender,
            borrowOffer,
            sig(borrowOffer, borrowerSK),
            callbackAddress,
            abi.encode(address(loanToken), 100)
        );
        assertEq(LendCallback(callbackAddress).recordedData(), abi.encode(address(loanToken), 100));
    }

    function testTakeConsistentPrices() public {
        lendOffer.expiry = lendOffer.start;
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender bond shares");
    }

    function testTakeMaturityPassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert("maturity");
        morphoV2.take(obligation, 100, 0, lender, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeLendOfferCollateralMissing() public {
        lendOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeLendOfferLLTVMismatch() public {
        lendOffer.collaterals[0].lltv = 0.5e18;

        vm.expectRevert("LLTVs do not match");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeLendmakeraclesMismatch() public {
        lendOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeBorrowOfferTooMuchCollaterals() public {
        borrowOffer.collaterals[0].token = address(0);

        vm.expectRevert(stdError.indexOOBError);
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }

    function testTakeBorrowOfferLLTVMismatch() public {
        borrowOffer.collaterals[0].lltv = 0.99e18;

        vm.expectRevert("LLTVs do not match");
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }

    function testTakeBorrowmakeraclesMismatch() public {
        borrowOffer.collaterals[0].oracle = address(0);

        vm.expectRevert("Oracles do not match");
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }

    function testTakeSellerMakerNotHealthyMaker() public {
        morphoV2.withdrawCollateral(obligation, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        morphoV2.take(obligation, 100, 0, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }

    function testTakeSellerTakerNotHealthy() public {
        morphoV2.withdrawCollateral(obligation, address(collateralToken1), 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeOfferWrongLoanToken(address _loanToken) public {
        vm.assume(_loanToken != address(loanToken));
        lendOffer.loanToken = _loanToken;
        lendOffer.expiry = block.timestamp + 200;
        vm.expectRevert("Loan tokens do not match");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeOfferWrongMaturity(uint256 _maturity) public {
        vm.assume(_maturity != obligation.maturity);
        lendOffer.maturity = _maturity;
        lendOffer.expiry = block.timestamp + 200;
        vm.expectRevert("Maturities do not match");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testTakeWrongSignature(Offer memory _offer) public {
        vm.prank(lendOffer.maker);
        morphoV2.setAuthorized(address(this), false);
        vm.assume(keccak256(abi.encode(_offer)) != keccak256(abi.encode(lendOffer)));
        vm.expectRevert("offer not ratified");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(_offer, lenderSK), address(0), hex"");
    }

    function testTakeInvalidSignature() public {
        vm.prank(lendOffer.maker);
        morphoV2.setAuthorized(address(this), false);

        vm.expectRevert("offer not ratified");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, Signature(0, 0, 0), address(0), hex"");
    }

    function testTakeInconsistentPrices() public {
        lendOffer.expiryPrice = 0.98 ether;
        lendOffer.expiry = lendOffer.start;
        vm.expectRevert("inconsistent prices");
        morphoV2.take(obligation, 100, 0, borrower, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testOrderNotAuthorized(address taker, address sender) public {
        vm.assume(sender != address(this));
        vm.assume(taker != sender);

        vm.expectRevert("order not authorized");
        vm.prank(sender);
        morphoV2.take(obligation, 100, 0, taker, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        uint256 snap = vm.snapshotState();

        vm.prank(taker);
        morphoV2.take(obligation, 0, 0, taker, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");

        vm.revertToState(snap);

        vm.prank(taker);
        morphoV2.setAuthorized(sender, true);
        vm.prank(sender);
        morphoV2.take(obligation, 0, 0, taker, lendOffer, sig(lendOffer, lenderSK), address(0), hex"");
    }

    function testOfferNotAuthorized(uint256 makerSK, address sender, uint256 otherSK) public {
        makerSK = boundPrivateKey(makerSK);
        otherSK = boundPrivateKey(otherSK);
        vm.assume(otherSK != makerSK);
        address maker = vm.addr(makerSK);
        vm.assume(sender != maker);
        vm.assume(sender != address(this));

        lendOffer.maker = maker;

        vm.expectRevert("offer not ratified");
        vm.prank(sender);
        morphoV2.take(obligation, 100, 0, sender, lendOffer, sig(lendOffer, otherSK), address(0), hex"");

        uint256 snap = vm.snapshotState();

        vm.prank(maker);
        morphoV2.take(obligation, 0, 0, maker, lendOffer, sig(lendOffer, otherSK), address(0), hex"");

        vm.revertToState(snap);

        vm.prank(sender);
        morphoV2.take(obligation, 0, 0, sender, lendOffer, sig(lendOffer, makerSK), address(0), hex"");

        vm.revertToState(snap);

        vm.prank(maker);
        morphoV2.setAuthorized(sender, true);
        vm.prank(sender);
        morphoV2.take(obligation, 0, 0, sender, lendOffer, sig(lendOffer, otherSK), address(0), hex"");

        vm.revertToStateAndDelete(snap);

        vm.prank(maker);
        morphoV2.setRatified(lendOffer, true);
        vm.prank(sender);
        morphoV2.take(obligation, 0, 0, sender, lendOffer, sig(lendOffer, otherSK), address(0), hex"");
    }
}

contract BorrowCallback is ICallbacks {
    bytes public recordedData;

    function onTake(Obligation memory obligation, address borrower, uint256, bytes memory data) external {
        recordedData = data;
        (address collateralToken, uint256 amount) = abi.decode(data, (address, uint256));
        ERC20(collateralToken).approve(msg.sender, amount);
        MorphoV2(msg.sender).supplyCollateral(obligation, collateralToken, amount, borrower);
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}

contract LendCallback is ICallbacks {
    bytes public recordedData;

    function onTake(Obligation memory obligation, address maker, uint256 assets, bytes memory data) external {
        recordedData = data;
        ERC20(obligation.loanToken).transfer(maker, assets);
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}
