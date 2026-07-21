// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest, LIQUIDATION_CURSOR, LLTV, MAX_TEST_AMOUNT} from "../BaseTest.sol";
import {Market, CollateralParams, Offer} from "../../src/interfaces/IMidnight.sol";
import {DeltaNeutralCallback} from "../../src/callback/DeltaNeutralCallback.sol";
import {WAD} from "../../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../../src/libraries/TickLib.sol";
import {Oracle} from "../helpers/Oracle.sol";

contract DeltaNeutralCallbackTest is BaseTest {
    DeltaNeutralCallback internal callback;
    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        callback = new DeltaNeutralCallback(address(midnight));

        midnight.enableLltv(WAD);

        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 30 days;
        market.collateralParams.push(
            CollateralParams({
                token: address(loanToken),
                lltv: WAD,
                liquidationCursor: LIQUIDATION_CURSOR,
                oracle: address(new Oracle())
            })
        );
        id = toId(market);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(callback), true, borrower);
        vm.prank(borrower);
        loanToken.approve(address(callback), type(uint256).max);
    }

    function lenderOffer() internal view returns (Offer memory offer) {
        offer.market = market;
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = type(uint128).max;
        offer.ratifier = address(dummyRatifier);
        offer.start = vm.getBlockTimestamp();
        offer.expiry = vm.getBlockTimestamp() + 1 days;
        offer.tick = MAX_TICK; // price == WAD, so units == assets.
        offer.continuousFeeCap = type(uint256).max;
    }

    /// @dev Opens a delta-neutral position for the borrower: takes `units` from a lender buy offer, using the
    /// callback as the seller (taker) callback so the loan-token collateral leg tracks the new debt.
    function openPosition(uint256 units) internal {
        deal(address(loanToken), lender, units);
        Offer memory offer = lenderOffer();

        vm.prank(borrower);
        midnight.take(offer, hex"", units, borrower, borrower, address(callback), hex"");
    }

    function testOnSellSuppliesCollateralMatchingDebtIncrease(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);

        openPosition(units);

        assertEq(midnight.debt(id, borrower), units, "debt");
        assertEq(midnight.collateral(id, borrower, 0), units, "collateral");
        assertEq(loanToken.balanceOf(address(callback)), 0, "callback balance");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower balance");
    }

    function testOnRepayWithdrawsCollateralMatchingDebtDecrease(uint256 units, uint256 repaidUnits) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaidUnits = bound(repaidUnits, 1, units);

        openPosition(units);

        vm.prank(borrower);
        midnight.repay(market, repaidUnits, borrower, address(callback), hex"");

        assertEq(midnight.debt(id, borrower), units - repaidUnits, "debt");
        assertEq(midnight.collateral(id, borrower, 0), units - repaidUnits, "collateral");
        assertEq(loanToken.balanceOf(address(callback)), 0, "callback balance");
    }

    function testOnRepayFullyUnwindsPosition(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);

        openPosition(units);

        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(callback), hex"");

        assertEq(midnight.debt(id, borrower), 0, "debt");
        assertEq(midnight.collateral(id, borrower, 0), 0, "collateral");
        assertEq(midnight.collateralBitmap(id, borrower), 0, "collateralBitmap");
    }

    function testOnBuyWithdrawsCollateralWhenBuyerNetsDownDebt(uint256 units, uint256 buybackUnits) public {
        units = bound(units, 2, MAX_TEST_AMOUNT);
        buybackUnits = bound(buybackUnits, 1, units - 1);

        openPosition(units);

        // otherBorrower posts a sell offer (i.e. is willing to increase their own debt); the borrower takes it as
        // buyer, netting down their pre-existing debt by buybackUnits.
        collateralize(market, otherBorrower, buybackUnits);

        Offer memory offer;
        offer.market = market;
        offer.buy = false;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.maxUnits = type(uint128).max;
        offer.ratifier = address(dummyRatifier);
        offer.start = vm.getBlockTimestamp();
        offer.expiry = vm.getBlockTimestamp() + 1 days;
        offer.tick = MAX_TICK;
        offer.continuousFeeCap = type(uint256).max;

        vm.prank(borrower);
        midnight.take(offer, hex"", buybackUnits, borrower, address(0), address(callback), hex"");

        assertEq(midnight.debt(id, borrower), units - buybackUnits, "debt");
        assertEq(midnight.collateral(id, borrower, 0), units - buybackUnits, "collateral");
        assertEq(loanToken.balanceOf(address(callback)), 0, "callback balance");
        assertEq(loanToken.balanceOf(otherBorrower), buybackUnits, "otherBorrower balance");
    }

    function testDeltaNeutralIndexRevertsWhenNotFound() public {
        Market memory otherMarket = market;
        otherMarket.collateralParams = new CollateralParams[](1);
        otherMarket.collateralParams[0] =
            CollateralParams({token: address(collateralToken1), lltv: LLTV, liquidationCursor: LIQUIDATION_CURSOR, oracle: address(oracle1)});

        vm.expectRevert(DeltaNeutralCallback.CollateralNotFound.selector);
        callback.deltaNeutralIndex(otherMarket);
    }

    function testOnSellRevertsWhenNotCalledByMidnight() public {
        vm.expectRevert(DeltaNeutralCallback.Unauthorized.selector);
        callback.onSell(id, market, 0, 0, 0, borrower, borrower, hex"");
    }

    function testOnRepayRevertsWhenNotCalledByMidnight() public {
        vm.expectRevert(DeltaNeutralCallback.Unauthorized.selector);
        callback.onRepay(id, market, 0, borrower, hex"");
    }

    function testOnBuyRevertsWhenNotCalledByMidnight() public {
        vm.expectRevert(DeltaNeutralCallback.Unauthorized.selector);
        callback.onBuy(id, market, 0, 0, 0, borrower, hex"");
    }
}
