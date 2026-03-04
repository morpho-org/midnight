// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {TakeAmountsLib} from "../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes20 internal id;
    Offer internal offer;

    uint256 internal initialUnits;
    uint256 internal initialShares;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken2),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        offer.buy = false;
        offer.obligationShares = type(uint256).max;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = TICK_RANGE;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = midnight.totalUnits(id);
        initialShares = midnight.totalShares(id);
    }

    function _setFees(uint256 fee0, uint256 fee1) internal returns (uint256 tradingFee) {
        fee0 = bound(fee0, 0, midnight.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        midnight.setObligationTradingFee(id, 0, fee0);
        midnight.setObligationTradingFee(id, 1, fee1);
        tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
    }

    /// @dev Returns the highest tick such that tickToPrice(tick) + tradingFee <= WAD.
    function _maxTick(uint256 tradingFee) internal pure returns (uint256) {
        uint256 maxPrice = WAD - tradingFee;
        uint256 t = TickLib.priceToTick(maxPrice);
        return TickLib.tickToPrice(t) > maxPrice ? t - 1 : t;
    }

    /// @dev Creates an initial borrowing position so borrower has debt and lender has obligation shares.
    function _createPosition(uint256 positionUnits) internal returns (uint256 currentUnits, uint256 currentShares) {
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, positionUnits);
        uint256 positionShares = TakeAmountsLib.unitsToShares(midnight, id, borrower, offer, positionUnits);
        offer.maker = borrower;
        offer.tick = 1;
        take(positionShares, lender, offer);
        currentUnits = midnight.totalUnits(id);
        currentShares = midnight.totalShares(id);
    }

    // All tests use a sell offer (offer.buy = false).
    // sellerPrice = price, buyerPrice = price + fee.

    // buyerIsLender = true: buyer = taker (lender, no debt), seller = maker (borrower).

    function testUnitsToSharesBuyerIsLender(uint256 targetUnits, uint256 tick, uint256 fee0, uint256 fee1) public {
        _setFees(fee0, fee1);
        targetUnits = bound(targetUnits, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        uint256 shares = TakeAmountsLib.unitsToShares(midnight, id, lender, offer, targetUnits);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, targetUnits);
        offer.maker = borrower;
        offer.tick = tick;

        (,, uint256 obligationUnits,) = take(shares, lender, offer);

        assertEq(obligationUnits, targetUnits, "e2e units");
    }

    function testBuyerAssetsToSharesBuyerIsLender(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        uint256 tradingFee = _setFees(fee0, fee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        offer.tick = tick;
        uint256 shares = TakeAmountsLib.buyerAssetsToShares(midnight, id, lender, offer, targetBuyerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));
        offer.maker = borrower;

        (uint256 buyerAssets,,,) = take(shares, lender, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToSharesBuyerIsLender(uint256 targetSellerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        _setFees(fee0, fee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        offer.tick = tick;
        uint256 shares = TakeAmountsLib.sellerAssetsToShares(midnight, id, lender, offer, targetSellerAssets);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));
        offer.maker = borrower;

        (, uint256 sellerAssets,,) = take(shares, lender, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerIsLender = false: buyer = taker (borrower, has debt), seller = maker (lender, has obligation shares).

    function testUnitsToSharesBuyerIsBorrower(uint256 targetUnits, uint256 tick, uint256 fee0, uint256 fee1) public {
        _setFees(fee0, fee1);
        targetUnits = bound(targetUnits, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        _createPosition(2 * targetUnits);

        uint256 shares = TakeAmountsLib.unitsToShares(midnight, id, borrower, offer, targetUnits);
        deal(address(loanToken), borrower, type(uint256).max);
        offer.maker = lender;
        offer.tick = tick;

        (,, uint256 obligationUnits,) = take(shares, borrower, offer);

        assertEq(obligationUnits, targetUnits, "e2e units");
    }

    function testBuyerAssetsToSharesBuyerIsBorrower(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        uint256 tradingFee = _setFees(fee0, fee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, _maxTick(tradingFee));

        _createPosition(1e36);

        offer.maker = lender;
        offer.tick = tick;
        uint256 shares = TakeAmountsLib.buyerAssetsToShares(midnight, id, borrower, offer, targetBuyerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (uint256 buyerAssets,,,) = take(shares, borrower, offer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToSharesBuyerIsBorrower(
        uint256 targetSellerAssets,
        uint256 tick,
        uint256 fee0,
        uint256 fee1
    ) public {
        _setFees(fee0, fee1);
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        _createPosition(1e36);

        offer.maker = lender;
        offer.tick = tick;
        uint256 shares = TakeAmountsLib.sellerAssetsToShares(midnight, id, borrower, offer, targetSellerAssets);
        deal(address(loanToken), borrower, type(uint256).max);

        (, uint256 sellerAssets,,) = take(shares, borrower, offer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // buyerPrice >= WAD: not all buyerAssets are reachable, but snapped values are.

    function testSnappedBuyerAssetsBuyerIsLender(uint256 targetBuyerAssets, uint256 fee0, uint256 fee1) public {
        uint256 tradingFee = _setFees(fee0, fee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        uint256 buyerPrice = TickLib.tickToPrice(TICK_RANGE) + tradingFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        uint256 shares = TakeAmountsLib.unitsToShares(midnight, id, lender, offer, targetUnits);
        deal(address(loanToken), lender, type(uint256).max);
        collateralize(obligation, borrower, shares.mulDivUp(initialUnits + 1, initialShares + 1));
        offer.maker = borrower;
        offer.tick = TICK_RANGE;

        (uint256 buyerAssets,,,) = take(shares, lender, offer);

        assertEq(
            buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivDown(buyerPrice, WAD), "e2e buyerAssets"
        );
    }

    function testSnappedBuyerAssetsBuyerIsBorrower(uint256 targetBuyerAssets, uint256 fee0, uint256 fee1) public {
        uint256 tradingFee = _setFees(fee0, fee1);
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);

        _createPosition(1e36);

        uint256 buyerPrice = TickLib.tickToPrice(TICK_RANGE) + tradingFee;
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);

        uint256 shares = TakeAmountsLib.unitsToShares(midnight, id, borrower, offer, targetUnits);
        deal(address(loanToken), borrower, type(uint256).max);
        offer.maker = lender;
        offer.tick = TICK_RANGE;

        (uint256 buyerAssets,,,) = take(shares, borrower, offer);

        assertEq(
            buyerAssets, targetBuyerAssets.mulDivUp(WAD, buyerPrice).mulDivDown(buyerPrice, WAD), "e2e buyerAssets"
        );
    }
}
