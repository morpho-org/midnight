// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD, DEFAULT_TICK_SPACING} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {TakeAmountsLib} from "../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;
    Offer internal offer;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);
        market.rcfThreshold = 0;

        id = toId(market);

        offer.buy = false;
        offer.maxUnits = type(uint256).max;
        offer.market = market;
        offer.ratifier = address(dummyRatifier);
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;

        createBadDebt(market); // to create non trivial lossFactor.
    }

    function _setSettlementFees(uint256 settlementFee0, uint256 settlementFee1)
        internal
        returns (uint256 settlementFee)
    {
        settlementFee0 = bound(settlementFee0, 0, maxSettlementFee(0)) / 1e12 * 1e12;
        settlementFee1 = bound(settlementFee1, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        midnight.touchMarket(market);
        midnight.setMarketSettlementFee(id, 0, settlementFee0);
        midnight.setMarketSettlementFee(id, 1, settlementFee1);
        settlementFee = midnight.settlementFee(id, market.maturity - vm.getBlockTimestamp());
    }

    /// @dev Returns the highest tick such that tickToPrice(tick) + settlementFee <= WAD.
    function _maxTick(uint256 settlementFee) internal pure returns (uint256) {
        uint256 maxPrice = WAD - settlementFee;
        uint256 t = TickLib.priceToTick(maxPrice, 1);
        return TickLib.tickToPrice(t) > maxPrice ? t - 1 : t;
    }

    /// @dev Creates an initial borrowing position so borrower has debt and lender has units.
    function _createPosition(uint256 positionUnits) internal {
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(market, borrower, positionUnits);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.tick = 896; // Low tick with a small positive price.
        take(positionUnits, lender, offer);
    }

    // All tests use a sell offer (offer.buy = false).
    // sellerPrice = price, buyerPrice = price + fee.

    // buyerIsLender = true: buyer = taker (lender, no debt), seller = maker (borrower).

    function testBuyerAssetsToUnitsBuyerIsLender(
        uint256 targetBuyerAssets,
        uint256 tick,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 4, _maxTick(settlementFee) / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;

        offer.tick = tick;
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(address(midnight), id, offer, targetBuyerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(market, borrower, units);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;

        (uint256 buyerAssets,) = take(units, lender, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsBuyerIsLender(
        uint256 targetSellerAssets,
        uint256 tick,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 4, _maxTick(settlementFee) / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;

        offer.tick = tick;
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(address(midnight), id, offer, targetSellerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(market, borrower, units);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;

        (, uint256 sellerAssets) = take(units, lender, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerIsLender = false: buyer = taker (borrower, has debt), seller = maker (lender, has units).

    function testBuyerAssetsToUnitsBuyerIsBorrower(
        uint256 targetBuyerAssets,
        uint256 tick,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 4, _maxTick(settlementFee) / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;

        _createPosition(1e36);

        offer.maker = lender;
        offer.receiverIfMakerIsSeller = lender;
        offer.tick = tick;
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(address(midnight), id, offer, targetBuyerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (uint256 buyerAssets,) = take(units, borrower, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsBuyerIsBorrower(
        uint256 targetSellerAssets,
        uint256 tick,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 4, _maxTick(settlementFee) / DEFAULT_TICK_SPACING) * DEFAULT_TICK_SPACING;

        _createPosition(1e36);

        offer.maker = lender;
        offer.receiverIfMakerIsSeller = lender;
        offer.tick = tick;
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(address(midnight), id, offer, targetSellerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (, uint256 sellerAssets) = take(units, borrower, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerPrice >= WAD: not all buyerAssets are reachable, but snapped values are.

    function testSnappedBuyerAssetsBuyerIsLender(
        uint256 targetBuyerAssets,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        uint256 buyerPrice = TickLib.tickToPrice(MAX_TICK) + settlementFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        deal(address(loanToken), lender, type(uint256).max);
        collateralize(market, borrower, targetUnits);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.tick = MAX_TICK;

        (uint256 buyerAssets,) = take(targetUnits, lender, offer);

        assertEq(buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivUp(buyerPrice, WAD), "e2e buyerAssets");
    }

    function testSnappedBuyerAssetsBuyerIsBorrower(
        uint256 targetBuyerAssets,
        uint256 settlementFee0,
        uint256 settlementFee1
    ) public {
        uint256 settlementFee = _setSettlementFees(settlementFee0, settlementFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        _createPosition(1e36);

        uint256 buyerPrice = TickLib.tickToPrice(MAX_TICK) + settlementFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        deal(address(loanToken), borrower, type(uint256).max);
        offer.maker = lender;
        offer.tick = MAX_TICK;

        (uint256 buyerAssets,) = take(targetUnits, borrower, offer);

        assertEq(buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivUp(buyerPrice, WAD), "e2e buyerAssets");
    }
}
