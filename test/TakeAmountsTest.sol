// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {TakeAmountsLib} from "../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal offer;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        offer.buy = false;
        offer.maxUnits = type(uint256).max;
        offer.obligation = obligation;
        offer.ratifier = address(ecrecoverRatifier);
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;

        createBadDebt(obligation); // to create non trivial lossFactor.
    }

    function _setTradingFees(uint256 tradingFee0, uint256 tradingFee1) internal returns (uint256 tradingFee) {
        tradingFee0 = bound(tradingFee0, 0, maxTradingFee(0)) / 1e12 * 1e12;
        tradingFee1 = bound(tradingFee1, 0, maxTradingFee(1)) / 1e12 * 1e12;
        midnight.touchObligation(obligation);
        midnight.setObligationTradingFee(id, 0, tradingFee0);
        midnight.setObligationTradingFee(id, 1, tradingFee1);
        tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
    }

    /// @dev Returns the highest tick such that tickToPrice(tick) + tradingFee <= WAD.
    function _maxTick(uint256 tradingFee) internal pure returns (uint256) {
        uint256 maxPrice = WAD - tradingFee;
        uint256 t = TickLib.priceToTick(maxPrice);
        return TickLib.tickToPrice(t) > maxPrice ? t - 1 : t;
    }

    /// @dev Creates an initial borrowing position so borrower has debt and lender has units.
    function _createPosition(uint256 positionUnits) internal {
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, positionUnits);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.tick = 1; // Use a low tick to ensure buyerPrice <= WAD even with fees.
        take(positionUnits, lender, offer);
    }

    // All tests use a sell offer (offer.buy = false).
    // sellerPrice = price, buyerPrice = price + fee.

    // buyerIsLender = true: buyer = taker (lender, no debt), seller = maker (borrower).

    function testBuyerAssetsToUnitsBuyerIsLender(
        uint256 targetBuyerAssets,
        uint256 tick,
        uint256 tradingFee0,
        uint256 tradingFee1
    ) public {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        offer.tick = tick;
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(address(midnight), id, offer, targetBuyerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, units);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;

        (uint256 buyerAssets,,) = take(units, lender, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsBuyerIsLender(
        uint256 targetSellerAssets,
        uint256 tick,
        uint256 tradingFee0,
        uint256 tradingFee1
    ) public {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        offer.tick = tick;
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(address(midnight), id, offer, targetSellerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, units);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;

        (, uint256 sellerAssets,) = take(units, lender, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerIsLender = false: buyer = taker (borrower, has debt), seller = maker (lender, has units).

    function testBuyerAssetsToUnitsBuyerIsBorrower(
        uint256 targetBuyerAssets,
        uint256 tick,
        uint256 tradingFee0,
        uint256 tradingFee1
    ) public {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        _createPosition(1e36);

        offer.maker = lender;
        offer.receiverIfMakerIsSeller = lender;
        offer.tick = tick;
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(address(midnight), id, offer, targetBuyerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (uint256 buyerAssets,,) = take(units, borrower, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsBuyerIsBorrower(
        uint256 targetSellerAssets,
        uint256 tick,
        uint256 tradingFee0,
        uint256 tradingFee1
    ) public {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        _createPosition(1e36);

        offer.maker = lender;
        offer.receiverIfMakerIsSeller = lender;
        offer.tick = tick;
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(address(midnight), id, offer, targetSellerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (, uint256 sellerAssets,) = take(units, borrower, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerPrice >= WAD: not all buyerAssets are reachable, but snapped values are.

    function testSnappedBuyerAssetsBuyerIsLender(uint256 targetBuyerAssets, uint256 tradingFee0, uint256 tradingFee1)
        public
    {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        uint256 buyerPrice = TickLib.tickToPrice(MAX_TICK) + tradingFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, targetUnits);
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.tick = MAX_TICK;

        (uint256 buyerAssets,,) = take(targetUnits, lender, offer);

        assertEq(buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivUp(buyerPrice, WAD), "e2e buyerAssets");
    }

    function testSnappedBuyerAssetsBuyerIsBorrower(uint256 targetBuyerAssets, uint256 tradingFee0, uint256 tradingFee1)
        public
    {
        uint256 tradingFee = _setTradingFees(tradingFee0, tradingFee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        _createPosition(1e36);

        uint256 buyerPrice = TickLib.tickToPrice(MAX_TICK) + tradingFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        deal(address(loanToken), borrower, type(uint256).max);
        offer.maker = lender;
        offer.tick = MAX_TICK;

        (uint256 buyerAssets,,) = take(targetUnits, borrower, offer);

        assertEq(buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivUp(buyerPrice, WAD), "e2e buyerAssets");
    }
}
