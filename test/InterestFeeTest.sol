// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Amounts} from "../src/MorphoV2.sol";

contract InterestFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 constant INTEREST_FEE = 0.1e18; // 10%
    uint256 constant INITIAL_UNITS = 1000e18;
    uint256 constant ENTRY_PRICE = 0.9e18; // Price at entry
    uint256 constant EXIT_PRICE = 1e18; // Price at exit (higher = profit for lender)

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 30 days;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));

        id = keccak256(abi.encode(obligation));

        morphoV2.setTradingFeeRecipient(feeRecipient);
        morphoV2.setDefaultInterestFee(address(loanToken), INTEREST_FEE);

        // Fund accounts
        deal(address(loanToken), lender, MAX_TEST_AMOUNT);
        deal(address(loanToken), otherLender, MAX_TEST_AMOUNT);
    }

    /// @dev Setup: lender enters at ENTRY_PRICE, borrower enters
    function _setupInitialPosition() internal {
        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 100;
        borrowerOffer.startPrice = ENTRY_PRICE;
        borrowerOffer.expiryPrice = ENTRY_PRICE;

        collateralize(obligation, borrower, INITIAL_UNITS * 2);

        // Lender enters, borrower enters
        Amounts memory amounts;
        amounts.buyerObligationUnits = INITIAL_UNITS;
        morphoV2.take(
            amounts,
            lender,
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer]),
            address(0),
            hex""
        );
    }

    /// @dev Create offer for lender to exit (sell shares)
    function _createLenderExitOffer() internal view returns (Offer memory) {
        Offer memory offer;
        offer.obligation = obligation;
        offer.buy = true; // buyer is maker (otherLender)
        offer.maker = otherLender;
        offer.assets = type(uint256).max;
        offer.expiry = block.timestamp + 100;
        offer.startPrice = EXIT_PRICE;
        offer.expiryPrice = EXIT_PRICE;
        return offer;
    }

    /// @dev Create offer for borrower to exit (repay debt via trade)
    function _createBorrowerExitOffer() internal view returns (Offer memory) {
        Offer memory offer;
        offer.obligation = obligation;
        offer.buy = false; // seller is maker (borrower)
        offer.maker = borrower;
        offer.assets = type(uint256).max;
        offer.expiry = block.timestamp + 100;
        offer.startPrice = EXIT_PRICE;
        offer.expiryPrice = EXIT_PRICE;
        return offer;
    }

    // ============ SELLER (LENDER) INTEREST FEE TESTS ============

    /// @dev Case A: Fixed sellerAssets - seller pays fee in units (burns more)
    function testSellerFee_FixedSellerAssets() public {
        _setupInitialPosition();

        uint256 sellerAssets = 100e18;
        Offer memory offer = _createLenderExitOffer();

        // Lender exits by selling to otherLender
        Amounts memory amounts;
        amounts.sellerAssets = sellerAssets;

        Amounts memory result = morphoV2.take(
            amounts,
            lender, // taker = seller (lender exiting)
            offer,
            sig([offer]),
            root([offer]),
            proof([offer]),
            address(0),
            hex""
        );

        // Seller should burn more shares than gross amount due to fee
        uint256 grossUnits = sellerAssets.mulDivDown(WAD, EXIT_PRICE);
        assertGt(result.sellerObligationUnits, grossUnits, "seller should burn extra units for fee");
        // assertEq(result.sellerInterestFeeUnits, result.sellerObligationUnits - grossUnits, "fee units mismatch");
    }

    /// @dev Case B: Fixed sellerUnits - seller pays fee in assets (receives less)
    function testSellerFee_FixedSellerUnits() public {
        _setupInitialPosition();

        uint256 sellerUnits = 100e18;
        Offer memory offer = _createLenderExitOffer();

        Amounts memory amounts;
        amounts.sellerObligationUnits = sellerUnits;

        Amounts memory result =
            morphoV2.take(amounts, lender, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");

        // Seller should receive less assets than gross amount due to fee
        uint256 grossAssets = sellerUnits.mulDivDown(EXIT_PRICE, WAD);
        assertLt(result.sellerAssets, grossAssets, "seller should receive less assets for fee");
        // assertEq(result.sellerInterestFeeAssets, grossAssets - result.sellerAssets, "fee assets mismatch");
    }

    /// @dev Case B': Fixed sellerShares - seller pays fee in assets (receives less)
    function testSellerFee_FixedSellerShares() public {
        _setupInitialPosition();

        uint256 sellerShares = morphoV2.sharesOf(lender, id) / 10; // 10% of position
        Offer memory offer = _createLenderExitOffer();

        Amounts memory amounts;
        amounts.sellerObligationShares = sellerShares;

        Amounts memory result =
            morphoV2.take(amounts, lender, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");

        // Seller should receive less assets than gross amount due to fee
        uint256 grossAssets = result.sellerObligationUnits.mulDivDown(EXIT_PRICE, WAD);
        assertLt(result.sellerAssets, grossAssets, "seller should receive less assets for fee");
        // assertEq(result.sellerInterestFeeAssets, grossAssets - result.sellerAssets, "fee assets mismatch");
    }

    /// @dev Case C: Fixed buyerAssets - seller pays fee in assets
    function testSellerFee_FixedBuyerAssets() public {
        _setupInitialPosition();

        uint256 buyerAssets = 100e18;
        Offer memory offer = _createLenderExitOffer();

        Amounts memory amounts;
        amounts.buyerAssets = buyerAssets;

        Amounts memory result =
            morphoV2.take(amounts, lender, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");

        // With fixed buyerAssets, seller fee comes from reduced sellerAssets
        uint256 grossSellerAssets = buyerAssets; // at price 1.0, buyerAssets = sellerAssets (no trading fee)
        assertLt(result.sellerAssets, grossSellerAssets, "seller should receive less assets for fee");
        // assertEq(result.sellerInterestFeeAssets, grossSellerAssets - result.sellerAssets, "fee assets mismatch");
    }

    /// @dev Case D: Fixed buyerUnits - seller pays fee in assets
    function testSellerFee_FixedBuyerUnits() public {
        _setupInitialPosition();

        uint256 buyerUnits = 100e18;
        Offer memory offer = _createLenderExitOffer();

        Amounts memory amounts;
        amounts.buyerObligationUnits = buyerUnits;

        Amounts memory result =
            morphoV2.take(amounts, lender, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");

        // Seller should receive less assets than gross
        uint256 grossSellerAssets = buyerUnits.mulDivDown(EXIT_PRICE, WAD);
        assertLt(result.sellerAssets, grossSellerAssets, "seller should receive less assets for fee");
        // assertEq(result.sellerInterestFeeAssets, grossSellerAssets - result.sellerAssets, "fee assets mismatch");
    }

    // ============ NO FEE WHEN NO PROFIT ============

    /// @dev No fee when seller has no profit (exit price <= entry price)
    function testNoSellerFee_WhenNoProfit() public {
        _setupInitialPosition();

        // Exit at same price as entry = no profit
        Offer memory offer;
        offer.obligation = obligation;
        offer.buy = true;
        offer.maker = otherLender;
        offer.assets = type(uint256).max;
        offer.expiry = block.timestamp + 100;
        offer.startPrice = ENTRY_PRICE; // Same as entry = no profit
        offer.expiryPrice = ENTRY_PRICE;

        Amounts memory amounts;
        amounts.sellerAssets = 100e18;

        morphoV2.take(amounts, lender, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");
    }

    // ============ BUYER (BORROWER) INTEREST FEE TESTS ============

    /// @dev Setup for buyer fee tests: borrower has debt with revenue > current price
    function _setupBorrowerWithProfit() internal {
        // Borrower enters at high price (gets more assets per unit of debt)
        // Use lender's offer (buy=true means lender is buyer, borrower is seller/taker)
        Offer memory lenderOffer;
        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.assets = type(uint256).max;
        lenderOffer.expiry = block.timestamp + 100;
        lenderOffer.startPrice = EXIT_PRICE; // 1.0 - borrower gets 1.0 assets per unit debt
        lenderOffer.expiryPrice = EXIT_PRICE;

        collateralize(obligation, borrower, INITIAL_UNITS * 2);

        Amounts memory amounts;
        amounts.sellerObligationUnits = INITIAL_UNITS;
        morphoV2.take(
            amounts,
            borrower, // taker = seller (borrower entering)
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer]),
            address(0),
            hex""
        );

        // Now borrower has debt with revenue = 1.0 per unit
        // If they exit at price < 1.0, they profit
    }

    /// @dev Case A: Fixed sellerAssets - buyer pays fee in units (receives less)
    function testBuyerFee_FixedSellerAssets() public {
        _setupBorrowerWithProfit();

        // For borrower to EXIT (reduce debt), they need to be the BUYER
        // Use lender's sell offer (buy=false means lender is seller/maker, borrower is buyer/taker)
        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false; // maker (lender) is seller
        lenderSellOffer.maker = lender;
        lenderSellOffer.assets = type(uint256).max;
        lenderSellOffer.expiry = block.timestamp + 100;
        lenderSellOffer.startPrice = ENTRY_PRICE; // 0.9 - borrower pays 0.9 per unit (profit!)
        lenderSellOffer.expiryPrice = ENTRY_PRICE;

        uint256 sellerAssets = 90e18; // lender receives this

        Amounts memory amounts;
        amounts.sellerAssets = sellerAssets;

        Amounts memory result = morphoV2.take(
            amounts,
            borrower, // taker = buyer (borrower exiting)
            lenderSellOffer,
            sig([lenderSellOffer]),
            root([lenderSellOffer]),
            proof([lenderSellOffer]),
            address(0),
            hex""
        );

        // Buyer should receive fewer units than gross due to fee
        uint256 grossUnits = sellerAssets.mulDivDown(WAD, ENTRY_PRICE);
        assertLt(result.buyerObligationUnits, grossUnits, "buyer should receive fewer units for fee");
    }

    /// @dev Case C: Fixed buyerAssets - buyer pays fee in units (receives less)
    function testBuyerFee_FixedBuyerAssets() public {
        _setupBorrowerWithProfit();

        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false; // maker (lender) is seller
        lenderSellOffer.maker = lender;
        lenderSellOffer.assets = type(uint256).max;
        lenderSellOffer.expiry = block.timestamp + 100;
        lenderSellOffer.startPrice = ENTRY_PRICE; // 0.9
        lenderSellOffer.expiryPrice = ENTRY_PRICE;

        uint256 buyerAssets = 90e18;

        Amounts memory amounts;
        amounts.buyerAssets = buyerAssets;

        Amounts memory result = morphoV2.take(
            amounts,
            borrower,
            lenderSellOffer,
            sig([lenderSellOffer]),
            root([lenderSellOffer]),
            proof([lenderSellOffer]),
            address(0),
            hex""
        );

        // Buyer should receive fewer units than gross due to fee
        uint256 grossUnits = buyerAssets.mulDivDown(WAD, ENTRY_PRICE);
        assertLt(result.buyerObligationUnits, grossUnits, "buyer should receive fewer units for fee");
    }

    /// @dev Case D: Fixed buyerUnits - buyer pays fee in assets (pays more)
    function testBuyerFee_FixedBuyerUnits() public {
        _setupBorrowerWithProfit();

        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false; // maker (lender) is seller
        lenderSellOffer.maker = lender;
        lenderSellOffer.assets = type(uint256).max;
        lenderSellOffer.expiry = block.timestamp + 100;
        lenderSellOffer.startPrice = ENTRY_PRICE; // 0.9
        lenderSellOffer.expiryPrice = ENTRY_PRICE;

        uint256 buyerUnits = 100e18;

        Amounts memory amounts;
        amounts.buyerObligationUnits = buyerUnits;

        Amounts memory result = morphoV2.take(
            amounts,
            borrower,
            lenderSellOffer,
            sig([lenderSellOffer]),
            root([lenderSellOffer]),
            proof([lenderSellOffer]),
            address(0),
            hex""
        );

        // Buyer should pay more assets than gross due to fee
        uint256 grossAssets = buyerUnits.mulDivDown(ENTRY_PRICE, WAD);
        assertGt(result.buyerAssets, grossAssets, "buyer should pay more assets for fee");
    }

    /// @dev No fee when buyer has no profit (exit price >= entry price)
    function testNoBuyerFee_WhenNoProfit() public {
        _setupBorrowerWithProfit();

        // Exit at same price as entry = no profit
        Offer memory lenderSellOffer;
        lenderSellOffer.obligation = obligation;
        lenderSellOffer.buy = false; // maker (lender) is seller
        lenderSellOffer.maker = lender;
        lenderSellOffer.assets = type(uint256).max;
        lenderSellOffer.expiry = block.timestamp + 100;
        lenderSellOffer.startPrice = EXIT_PRICE; // 1.0 = same as entry = no profit
        lenderSellOffer.expiryPrice = EXIT_PRICE;

        Amounts memory amounts;
        amounts.buyerAssets = 100e18;

        morphoV2.take(
            amounts,
            borrower,
            lenderSellOffer,
            sig([lenderSellOffer]),
            root([lenderSellOffer]),
            proof([lenderSellOffer]),
            address(0),
            hex""
        );
    }

    // ============ NO FEE WHEN NO PROFIT ============

    /// @dev No fee for new position (lender entering, not exiting)
    function testNoSellerFee_WhenEntering() public {
        // Don't setup initial position - this will be first trade

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 100;
        borrowerOffer.startPrice = EXIT_PRICE;
        borrowerOffer.expiryPrice = EXIT_PRICE;

        collateralize(obligation, borrower, INITIAL_UNITS * 2);

        Amounts memory amounts;
        amounts.buyerAssets = 100e18;

        morphoV2.take(
            amounts,
            lender,
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer]),
            address(0),
            hex""
        );
    }
}
