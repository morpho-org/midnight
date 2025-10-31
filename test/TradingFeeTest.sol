// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {BaseTest} from "./BaseTest.sol";

contract TradingFeeTest is BaseTest {
    using MathLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

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

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = 100 ether;
        lenderOffer.start = block.timestamp;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = 100 ether;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        deal(address(loanToken), address(this), 1000 ether);
        deal(address(loanToken), address(lender), 1000 ether);
        deal(address(loanToken), address(borrower), 1000 ether);
        deal(obligation.collaterals[0].token, address(this), type(uint256).max);

        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 200 ether, borrower);

        morphoV2.setTradingFeeRecipient(feeRecipient);
    }

    // Fee proportional to interest.

    function testBuyerAssetsLend() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(WAD, WAD + fee.mulDivDown(WAD, price) - fee);
        uint256 expectedUnits = expectedSellerAssets.mulDivDown(WAD, price);
        uint256 expectedFee = (expectedUnits - expectedSellerAssets) * fee / WAD;

        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerAssetsBorrow() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 buyerAssets = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        uint256 expectedUnits = buyerAssets.mulDivDown(WAD, price);
        uint256 expectedSellerAssets = (buyerAssets - fee.mulDivDown(expectedUnits, WAD)).mulDivDown(WAD, WAD - fee);
        uint256 expectedFee = buyerAssets - expectedSellerAssets;

        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsLend() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        uint256 expectedUnits = sellerAssets.mulDivDown(WAD, price);
        uint256 expectedFee = (expectedUnits - sellerAssets) * fee / WAD;

        take(0, sellerAssets, 0, 0, lender, borrowerOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testSellerAssetsBorrow() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 sellerAssets = 90 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        uint256 expectedBuyerAssets =
            (sellerAssets.mulDivDown(WAD - fee, WAD)).mulDivDown(WAD, WAD - fee.mulDivDown(WAD, price));
        uint256 expectedFee = expectedBuyerAssets - sellerAssets;

        take(0, sellerAssets, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 200, "fee recipient balance");
    }

    function testObligationUnitsLend() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 obligationUnits = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        borrowerOffer.startPrice = price;
        borrowerOffer.expiryPrice = price;

        uint256 expectedSellerAssets = obligationUnits * price / WAD;
        uint256 expectedFee = (obligationUnits - expectedSellerAssets) * fee / WAD;

        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testObligationUnitsBorrow() public {
        morphoV2.setTradingFee(id, 1e18, 0.05e18);
        uint256 obligationUnits = 100 ether;
        uint256 price = 0.9 ether;
        uint256 fee = 0.05e18;

        lenderOffer.startPrice = price;
        lenderOffer.expiryPrice = price;

        uint256 expectedBuyerAssets = obligationUnits * price / WAD;
        uint256 expectedSellerAssets =
            (expectedBuyerAssets - fee.mulDivDown(obligationUnits, WAD)).mulDivDown(WAD, WAD - fee);
        uint256 expectedFee = expectedBuyerAssets - expectedSellerAssets;

        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    // Fee proportional to amount traded.

    function testBuyerAssetsLendMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 buyerAssets = 100 ether;
        borrowerOffer.startPrice = 0.9 ether;
        borrowerOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(WAD, WAD + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(buyerAssets, 0, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testBuyerAssetsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 buyerAssets = 100 ether;
        lenderOffer.startPrice = 0.9 ether;
        lenderOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = buyerAssets.mulDivDown(WAD, WAD + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(buyerAssets, 0, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsLendMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 sellerAssets = 100 ether;
        borrowerOffer.startPrice = 0.9 ether;
        borrowerOffer.expiryPrice = 0.9 ether;

        uint256 expectedFee = sellerAssets / 1000;

        take(0, sellerAssets, 0, 0, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testSellerAssetsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 sellerAssets = 90 ether;
        lenderOffer.startPrice = 0.9 ether;
        lenderOffer.expiryPrice = 0.9 ether;

        uint256 expectedFee = sellerAssets / 1000;

        take(0, sellerAssets, 0, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationUnitsLendMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 obligationUnits = 100 ether;
        borrowerOffer.startPrice = 0.9 ether;
        borrowerOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = obligationUnits * 0.9 ether / WAD;
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, obligationUnits, 0, lender, borrowerOffer);

        assertEq(loanToken.balanceOf(feeRecipient), expectedFee, "fee recipient balance");
    }

    function testObligationUnitsBorrowMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 obligationUnits = 100 ether;
        lenderOffer.startPrice = 0.9 ether;
        lenderOffer.expiryPrice = 0.9 ether;

        uint256 expectedBuyerAssets = obligationUnits * 0.9 ether / WAD;
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(WAD, WAD + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, obligationUnits, 0, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationSharesLendMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 obligationShares = 100 ether;
        borrowerOffer.startPrice = 0.9 ether;
        borrowerOffer.expiryPrice = 0.9 ether;

        uint256 expectedSellerAssets = obligationShares * 0.9 ether / WAD;
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, 0, obligationShares, lender, borrowerOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }

    function testObligationSharesBorrowMax() public {
        morphoV2.setTradingFee(id, 0.001e18, 0.05e18);
        uint256 obligationShares = 100 ether;
        lenderOffer.startPrice = 0.9 ether;
        lenderOffer.expiryPrice = 0.9 ether;

        uint256 expectedBuyerAssets = obligationShares * 0.9 ether / WAD;
        uint256 expectedSellerAssets = expectedBuyerAssets.mulDivDown(WAD, WAD + 0.001e18);
        uint256 expectedFee = expectedSellerAssets / 1000;

        take(0, 0, 0, obligationShares, borrower, lenderOffer);

        assertApproxEqAbs(loanToken.balanceOf(feeRecipient), expectedFee, 100, "fee recipient balance");
    }
}
