// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TakeTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;

    uint256 internal maxAssets = 1e36; // to refine.

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = keccak256(abi.encode(obligation));

        lendOffer.buy = true;
        lendOffer.maker = lender;
        lendOffer.assets = 100;
        lendOffer.obligation = obligation;
        lendOffer.start = block.timestamp;
        lendOffer.expiry = block.timestamp + 200;
        lendOffer.startPrice = 0.99 ether;
        lendOffer.expiryPrice = 0.99 ether;

        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = 100;
        borrowOffer.obligation = obligation;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 0.99 ether;
        borrowOffer.expiryPrice = 0.99 ether;

        deal(address(loanToken), address(this), 100);
        deal(address(loanToken), address(lender), 100);
        deal(address(obligation.collaterals[0].token), address(this), type(uint256).max);

        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 135, borrower);
    }

    function testTakePostMaturity(uint256 maturity) public {
        maturity = bound(maturity, 0, block.timestamp - 1);
        obligation.maturity = maturity;
        Offer memory offer;
        offer.expiry = block.timestamp;
        Signature memory sig;
        vm.expectRevert("maturity");
        morphoV2.take(100, 0, 0, 0, lender, offer, sig, root([offer]), proof([offer]), address(0), hex"");
    }

    function testLend() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 101, "borrower debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), 100, "borrower consumed");
    }

    function testBorrow() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 101, "obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 101, "lender debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(lender, 0), 100, "lender consumed");
        assertEq(loanToken.balanceOf(borrower), 100, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), 100, "lender consumed");
    }

    function testWithdrawSecondaryWithLender() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        (address otherLender, uint256 otherLenderSecretKey) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        deal(address(loanToken), otherLender, 100);
        lendOffer.maker = otherLender;
        morphoV2.take(
            0,
            0,
            101,
            0,
            lender,
            lendOffer,
            sig(root([lendOffer]), otherLenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(otherLender, id), 101, "other lender obligation shares");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(otherLender, 0), 99, "other lender consumed");
        assertEq(loanToken.balanceOf(lender), 99, "lender balance");
        assertEq(loanToken.balanceOf(otherLender), 1, "other lender balance");
    }

    function testWithdrawSecondaryWithBorrower() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );
        lendOffer.maker = borrower;
        lendOffer.group = bytes32(uint256(1));
        morphoV2.take(
            0,
            0,
            101,
            0,
            lender,
            lendOffer,
            sig(root([lendOffer]), borrowerSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.totalUnits(id), 0, "total obligations");
        assertEq(morphoV2.totalShares(id), 0, "total shares");
        assertEq(morphoV2.consumed(borrower, bytes32(uint256(1))), 99, "borrower consumed");
        assertEq(loanToken.balanceOf(lender), 99, "lender balance");
        assertEq(loanToken.balanceOf(borrower), 1, "borrower balance");
    }

    function testRepaySecondaryWithBorrower() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        (address otherBorrower, uint256 otherBorrowerSecretKey) = makeAddrAndKey("otherBorrower");
        vm.prank(otherBorrower);
        ERC20(obligation.collaterals[0].token).approve(address(morphoV2), 135);
        deal(obligation.collaterals[0].token, otherBorrower, 135);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 135, otherBorrower);
        borrowOffer.maker = otherBorrower;
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            borrowOffer,
            sig(root([borrowOffer]), otherBorrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.sharesOf(otherBorrower, id), 0, "other borrower obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 0, "borrower debt");
        assertEq(morphoV2.debtOf(otherBorrower, id), 101, "other borrower debt");
        assertEq(morphoV2.totalUnits(id), 101, "total obligations");
        assertEq(morphoV2.totalShares(id), 101, "total shares");
        assertEq(morphoV2.consumed(otherBorrower, 0), 100, "other borrower consumed");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(otherBorrower), 100, "other borrower balance");
    }

    function testRepaySecondaryWithLender() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        borrowOffer.maker = lender;
        borrowOffer.group = bytes32(uint256(1));
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            borrowOffer,
            sig(root([borrowOffer]), lenderSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 0, "lender obligation shares");
        assertEq(morphoV2.sharesOf(borrower, id), 0, "borrower obligation shares");
        assertEq(morphoV2.debtOf(borrower, id), 0, "borrower debt");
        assertEq(morphoV2.debtOf(lender, id), 0, "lender debt");
        assertEq(morphoV2.totalUnits(id), 0, "total obligations");
        assertEq(morphoV2.totalShares(id), 0, "total shares");
        assertEq(morphoV2.consumed(lender, bytes32(uint256(1))), 100, "lender consumed");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 100, "lender balance");
    }

    function testMatch() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            address(this),
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );
        morphoV2.take(
            0,
            0,
            101,
            0,
            address(this),
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(address(this), id), 0, "obligation shares");
        assertEq(morphoV2.debtOf(address(this), id), 0, "debt");
        assertEq(loanToken.balanceOf(address(this)), 99, "balance");
        assertEq(morphoV2.consumed(lender, 0), 99, "lender consumed");
        assertEq(morphoV2.consumed(borrower, 0), 100, "borrower consumed");
    }

    function testConsumed() public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        vm.expectRevert("consumed");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
    }

    function testTakePartialFill() public {
        morphoV2.take(
            50,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.consumed(lender, 0), 50);

        vm.expectRevert("consumed");
        morphoV2.take(
            51,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        morphoV2.take(
            50,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.consumed(lender, 0), 100);
    }

    function testTakeOCO() public {
        Offer memory lendOffer2 = lendOffer;
        lendOffer2.obligation.maturity = block.timestamp + 200;
        lendOffer2.expiry = block.timestamp + 200;
        Obligation memory obligation2 = obligation;
        obligation2.maturity = block.timestamp + 200;

        morphoV2.take(
            70,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        vm.expectRevert("consumed");
        morphoV2.take(
            31,
            0,
            0,
            0,
            borrower,
            lendOffer2,
            sig(root([lendOffer2]), lenderSecretKey),
            root([lendOffer2]),
            proof([lendOffer2]),
            address(0),
            hex""
        );

        morphoV2.supplyCollateral(obligation2, obligation2.collaterals[0].token, 134, borrower);

        morphoV2.take(
            30,
            0,
            0,
            0,
            borrower,
            lendOffer2,
            sig(root([lendOffer2]), lenderSecretKey),
            root([lendOffer2]),
            proof([lendOffer2]),
            address(0),
            hex""
        );
        assertEq(morphoV2.consumed(lender, 0), 100);
    }

    function testTakeLendBorrowCallback() public {
        (address otherBorrower, uint256 otherBorrowerSecretKey) = makeAddrAndKey("otherBorrower");
        borrowOffer.callbackAddress = address(new BorrowCallback());
        borrowOffer.callbackData = abi.encode(obligation.collaterals[0].token, 135);
        borrowOffer.maker = address(otherBorrower);
        deal(obligation.collaterals[0].token, borrowOffer.callbackAddress, 135);
        assertEq(morphoV2.collateralOf(otherBorrower, id, obligation.collaterals[0].token), 0);

        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), otherBorrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );
        assertEq(morphoV2.collateralOf(otherBorrower, id, obligation.collaterals[0].token), 135);
        assertEq(BorrowCallback(borrowOffer.callbackAddress).recordedData(), borrowOffer.callbackData);
    }

    function testTakeBorrowBorrowCallback() public {
        (address otherBorrower,) = makeAddrAndKey("otherBorrower");
        address callbackAddress = address(new BorrowCallback());
        deal(obligation.collaterals[0].token, callbackAddress, 135);
        assertEq(morphoV2.collateralOf(otherBorrower, id, obligation.collaterals[0].token), 0);

        morphoV2.take(
            100,
            0,
            0,
            0,
            otherBorrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            callbackAddress,
            abi.encode(obligation.collaterals[0].token, 135)
        );
        assertEq(morphoV2.collateralOf(otherBorrower, id, obligation.collaterals[0].token), 135);
        assertEq(BorrowCallback(callbackAddress).recordedData(), abi.encode(obligation.collaterals[0].token, 135));
    }

    function testTakeBorrowLendCallback() public {
        (address otherLender, uint256 otherLenderSecretKey) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        lendOffer.callbackAddress = address(new LendCallback());
        lendOffer.callbackData = abi.encode(address(loanToken), 100);
        lendOffer.maker = address(otherLender);
        deal(address(loanToken), lendOffer.callbackAddress, 100);

        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), otherLenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
        assertEq(LendCallback(lendOffer.callbackAddress).recordedData(), lendOffer.callbackData);
    }

    function testTakeLendLendCallback() public {
        (address otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), 100);
        address callbackAddress = address(new LendCallback());
        deal(address(loanToken), callbackAddress, 100);

        morphoV2.take(
            100,
            0,
            0,
            0,
            otherLender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            callbackAddress,
            abi.encode(address(loanToken), 100)
        );
        assertEq(LendCallback(callbackAddress).recordedData(), abi.encode(address(loanToken), 100));
    }

    function testTakeConsistentPrices() public {
        lendOffer.expiry = lendOffer.start;
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), 101, "lender shares");
    }

    function testTakeMaturityPassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert("maturity");
        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
    }

    function testTakeSellerMakerNotHealthyMaker() public {
        morphoV2.withdrawCollateral(obligation, obligation.collaterals[0].token, 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        morphoV2.take(
            100,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );
    }

    function testTakeSellerTakerNotHealthy() public {
        morphoV2.withdrawCollateral(obligation, obligation.collaterals[0].token, 1, borrower);
        vm.expectRevert("Seller is unhealthy");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
    }

    function testTakeWrongSignature(bytes32 wrongRoot) public {
        vm.assume(wrongRoot != root([lendOffer]));
        vm.expectRevert("invalid signature");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(wrongRoot, lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
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
            lendOffer,
            Signature({v: 0, r: 0, s: 0}),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
    }

    function testTakeInconsistentPrices() public {
        lendOffer.expiryPrice = 0.98 ether;
        lendOffer.expiry = lendOffer.start;
        vm.expectRevert("inconsistent prices");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
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
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
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
            lendOffer,
            sig(root([lendOffer, otherOffer]), lenderSecretKey),
            root([lendOffer, otherOffer]),
            proof,
            address(0),
            hex""
        );
    }

    function testTakeTwoLeaves(Offer memory otherOffer) public {
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer, otherOffer]), lenderSecretKey),
            root([lendOffer, otherOffer]),
            proof([lendOffer, otherOffer]),
            address(0),
            hex""
        );
    }

    // test inputs

    function setupFeesAndRounding() internal {
        morphoV2.setTradingFee(keccak256(abi.encode(obligation)), 0.05e18);
        morphoV2.setTradingFeeRecipient(address(this));

        address otherBorrower = makeAddr("otherBorrower");
        deal(obligation.collaterals[0].token, address(this), 135);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 135, otherBorrower);

        bytes32 initialGroup = lendOffer.group;
        lendOffer.group = keccak256("group");

        // realize some bad debt
        morphoV2.take(
            100,
            0,
            0,
            0,
            otherBorrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        Oracle(oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        morphoV2.liquidate(obligation, new Seizure[](1), otherBorrower, "");

        // reset
        lendOffer.group = initialGroup;
        Oracle(oracle).setPrice(ORACLE_PRICE_SCALE);
    }

    function testInputBuyerAssets(uint256 buyerAssets) public {
        setupFeesAndRounding();

        buyerAssets = bound(buyerAssets, 0, maxAssets);
        deal(address(loanToken), address(lender), buyerAssets);

        deal(obligation.collaterals[0].token, address(this), buyerAssets * 2);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, buyerAssets * 2, borrower);

        lendOffer.assets = buyerAssets;

        morphoV2.take(
            buyerAssets,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
    }

    function testInputSellerAssets(uint256 sellerAssets) public {
        setupFeesAndRounding();

        sellerAssets = bound(sellerAssets, 0, maxAssets);
        deal(address(loanToken), address(lender), sellerAssets * 2);

        deal(obligation.collaterals[0].token, address(this), sellerAssets * 2);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, sellerAssets * 2, borrower);

        lendOffer.assets = sellerAssets * 2;

        morphoV2.take(
            0,
            sellerAssets,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(borrower), sellerAssets, "borrower balance");
    }

    function testInputObligationUnits(uint256 obligationUnits) public {
        setupFeesAndRounding();

        obligationUnits = bound(obligationUnits, 1, maxAssets);
        deal(address(loanToken), address(lender), obligationUnits);

        deal(obligation.collaterals[0].token, address(this), obligationUnits * 2);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, obligationUnits * 2, borrower);

        lendOffer.assets = obligationUnits;

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.debtOf(borrower, id), obligationUnits, "borrower debt");
    }

    function testInputObligationShares(uint256 obligationShares) public {
        obligationShares = bound(obligationShares, 1, maxAssets);
        deal(address(loanToken), address(lender), obligationShares);

        deal(obligation.collaterals[0].token, address(this), obligationShares * 2);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, obligationShares * 2, borrower);

        lendOffer.assets = obligationShares;

        morphoV2.take(
            0,
            0,
            0,
            obligationShares,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );

        assertEq(morphoV2.sharesOf(lender, id), obligationShares, "lender shares");
    }

    function testNonce() public {
        vm.prank(lender);
        morphoV2.shuffleNonce();

        vm.expectRevert("invalid nonce");
        morphoV2.take(
            100,
            0,
            0,
            0,
            borrower,
            lendOffer,
            sig(root([lendOffer]), lenderSecretKey),
            root([lendOffer]),
            proof([lendOffer]),
            address(0),
            hex""
        );
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
        require(ERC20(obligation.loanToken).transfer(maker, assets), "transfer failed");
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external {}
}
