// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lendOffer;
    Offer internal borrowOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

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

        lendOffer.obligation = obligation;
        lendOffer.buy = true;
        lendOffer.maker = lender;
        lendOffer.assets = 100 ether;
        lendOffer.start = block.timestamp;
        lendOffer.expiry = block.timestamp + 200;
        lendOffer.startPrice = 1 ether;
        lendOffer.expiryPrice = 1 ether;

        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = 100 ether;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(this), 1000 ether);
        deal(address(loanToken), address(lender), 1000 ether);
        deal(address(loanToken), address(borrower), 1000 ether);
        deal(obligation.collaterals[0].token, address(this), type(uint256).max);

        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 200 ether, borrower);

        // Set up trading fee for tests
        morphoV2.setTradingFee(id, 0.05e18); // 5%
        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    function testTradingFeeSetup() public view {
        assertEq(morphoV2.tradingFee(id), 0.05e18, "trading fee percentage");
        assertEq(morphoV2.tradingFeeRecipient(), feeRecipient, "fee recipient");
    }

    function testBuyerAssetsWithFee() public {
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(1e18, 1e18 + fee.mulDivDown(1e18, price) - fee);
        uint256 expectedUnits = expectedSellerAssets.mulDivDown(1e18, price);
        uint256 expectedFee = (expectedUnits - expectedSellerAssets) * fee / 1e18;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            buyerAssets,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender balance");
        assertApproxEqAbs(morphoV2.sharesOf(lender, id), expectedUnits, 100, "units");
        assertApproxEqAbs(
            loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, 100, "fee recipient balance"
        );
        assertApproxEqAbs(
            loanToken.balanceOf(borrower), borrowerBalanceBefore + expectedSellerAssets, 100, "borrower balance"
        );
    }

    function testSellerAssetsWithFee() public {
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedUnits = sellerAssets.mulDivDown(1e18, price);
        uint256 expectedFee = (expectedUnits - sellerAssets) * fee / 1e18;
        uint256 expectedBuyerAssets = sellerAssets + expectedFee;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            0,
            sellerAssets,
            0,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "fee recipient balance");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + sellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - expectedBuyerAssets, "lender balance");
    }

    function testObligationUnitsWithFee() public {
        uint256 obligationUnits = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowOffer.startPrice = price;
        borrowOffer.expiryPrice = price;

        uint256 expectedSellerAssets = obligationUnits * price / 1e18;
        uint256 expectedFee = (obligationUnits - expectedSellerAssets) * fee / 1e18;
        uint256 expectedBuyerAssets = expectedSellerAssets + expectedFee;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "fee recipient balance");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + expectedSellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - expectedBuyerAssets, "lender balance");
    }

    function testZeroTradingFee() public {
        morphoV2.setTradingFee(id, 0);
        uint256 buyerAssets = 100 ether;
        borrowOffer.startPrice = 0.9 ether;
        borrowOffer.expiryPrice = 0.9 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            buyerAssets,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + buyerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender pays full amount");
    }

    function testBuyerAssetsNoInterest() public {
        uint256 buyerAssets = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            buyerAssets,
            0,
            0,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + buyerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - buyerAssets, "lender pays full amount");
    }

    function testSellerAssetsNoInterest() public {
        uint256 sellerAssets = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            0,
            sellerAssets,
            0,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + sellerAssets, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - sellerAssets, "lender pays full amount");
    }

    function testObligationUnitsNoInterest() public {
        uint256 obligationUnits = 100 ether;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        uint256 feeRecipientBalanceBefore = loanToken.balanceOf(feeRecipient);
        uint256 borrowerBalanceBefore = loanToken.balanceOf(borrower);
        uint256 lenderBalanceBefore = loanToken.balanceOf(lender);

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        assertEq(loanToken.balanceOf(feeRecipient), feeRecipientBalanceBefore, "no fee collected");
        assertEq(loanToken.balanceOf(borrower), borrowerBalanceBefore + obligationUnits, "borrower gets full amount");
        assertEq(loanToken.balanceOf(lender), lenderBalanceBefore - obligationUnits, "lender pays full amount");
    }
}
