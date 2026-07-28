// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD, CBP, maxSettlementFee as _maxSettlementFee} from "../src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {ConsumableUnitsLib} from "../src/periphery/ConsumableUnitsLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

/// @dev Minimal callback exposing `buyerAssetsBound` (and optionally reverting) to exercise the buy cap.
contract BuyerAssetsBoundMock {
    uint256 internal immutable BOUND;
    bool internal immutable REVERTS;

    constructor(uint256 bound, bool reverts) {
        BOUND = bound;
        REVERTS = reverts;
    }

    function buyerAssetsBound(bytes32, Market memory, address, bytes memory) external view returns (uint256) {
        require(!REVERTS);
        return BOUND;
    }
}

contract ConsumableUnitsLibTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;
    Offer internal offer;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle1)
                })
            );
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle2)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);

        id = toId(market);
        midnight.touchMarket(market);

        for (uint256 index = 0; index <= 6; index++) {
            uint256 fee = _maxSettlementFee(index) / CBP * CBP; // largest CBP-aligned fee for the index.
            midnight.setMarketSettlementFee(id, index, fee);
        }

        offer.market = market;
        offer.maker = borrower;
        offer.group = keccak256("consumable group");
        offer.tick = 4000;
        offer.maxUnits = 100e18;
    }

    function testFuzzMaxUnitsReturnsRemainingUnits(uint128 maxUnits, uint128 consumed) public {
        offer.maxUnits = maxUnits;

        _setConsumed(consumed);

        uint256 expectedUnits = uint256(maxUnits).zeroFloorSub(consumed);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
        if (consumed >= maxUnits) assertEq(expectedUnits, 0);
    }

    function testFuzzMaxAssetsBuyReturnsUnitsForRemainingBuyerAssets(uint128 maxAssets, uint128 consumed, uint256 tick)
        public
    {
        // Keep the tick above MAX_TICK / 2 so that the computation offerPrice - settlementFee doesn't revert.
        tick = bound(tick, MAX_TICK / 2, MAX_TICK);
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = 0;
        offer.maxAssets = maxAssets;
        offer.tick = tick;

        _setConsumed(consumed);

        uint256 remainingAssets = uint256(maxAssets).zeroFloorSub(consumed);
        uint256 buyerPrice = TickLib.tickToPrice(tick);
        uint256 expectedUnits = remainingAssets.mulDivUp(WAD, buyerPrice);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
        if (consumed >= maxAssets) assertEq(expectedUnits, 0);
    }

    function testFuzzMaxAssetsSellReturnsUnitsForRemainingSellerAssets(
        uint128 maxAssets,
        uint128 consumed,
        uint256 tick
    ) public {
        // Tick corresponding to a non-zero price, so that the expectedUnits computation doesn't revert.
        tick = bound(tick, 2, MAX_TICK);
        offer.maxUnits = 0;
        offer.maxAssets = maxAssets;
        offer.tick = tick;

        _setConsumed(consumed);

        uint256 remainingAssets = uint256(maxAssets).zeroFloorSub(consumed);
        uint256 sellerPrice = TickLib.tickToPrice(tick);
        uint256 expectedUnits = remainingAssets.mulDivDown(WAD, sellerPrice);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
        if (consumed >= maxAssets) assertEq(expectedUnits, 0);
    }

    function testFuzzMaxAssetsBuyCappedByCallbackBound(
        uint128 maxAssets,
        uint128 consumed,
        uint256 tick,
        uint256 assetsBound
    ) public {
        // Keep the tick above MAX_TICK / 2 so that the computation offerPrice - settlementFee doesn't revert.
        tick = bound(tick, MAX_TICK / 2, MAX_TICK);
        assetsBound = bound(assetsBound, 0, 1e30);
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = 0;
        offer.maxAssets = maxAssets;
        offer.tick = tick;
        offer.callback = address(new BuyerAssetsBoundMock(assetsBound, false));

        _setConsumed(consumed);

        uint256 remainingAssets = uint256(maxAssets).zeroFloorSub(consumed);
        uint256 buyerPrice = TickLib.tickToPrice(tick);
        uint256 uncappedUnits = remainingAssets.mulDivUp(WAD, buyerPrice);
        uint256 boundUnits = assetsBound.mulDivDown(WAD, buyerPrice);
        uint256 expectedUnits = UtilsLib.min(uncappedUnits, boundUnits);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
    }

    function testFuzzMaxUnitsBuyCappedByCallbackBound(
        uint128 maxUnits,
        uint128 consumed,
        uint256 tick,
        uint256 assetsBound
    ) public {
        tick = bound(tick, MAX_TICK / 2, MAX_TICK);
        assetsBound = bound(assetsBound, 0, 1e30);
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = maxUnits;
        offer.tick = tick;
        offer.callback = address(new BuyerAssetsBoundMock(assetsBound, false));

        _setConsumed(consumed);

        uint256 uncappedUnits = uint256(maxUnits).zeroFloorSub(consumed);
        uint256 boundUnits = assetsBound.mulDivDown(WAD, TickLib.tickToPrice(tick));
        uint256 expectedUnits = UtilsLib.min(uncappedUnits, boundUnits);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
    }

    function testBuyNotCappedWhenCallbackReverts(uint256 tick) public {
        tick = bound(tick, MAX_TICK / 2, MAX_TICK);
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = 100e18;
        offer.tick = tick;
        // Callback reverts on buyerAssetsBound: the staticcall fails, so no cap is applied.
        offer.callback = address(new BuyerAssetsBoundMock(0, true));

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), 100e18);
    }

    function testBuyNotCappedWhenNoCallback(uint256 tick) public {
        tick = bound(tick, MAX_TICK / 2, MAX_TICK);
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = 100e18;
        offer.tick = tick;
        // No callback (address(0)): the staticcall returns empty data, so no cap is applied.
        offer.callback = address(0);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), 100e18);
    }

    function _setConsumed(uint128 amount) internal {
        vm.prank(offer.maker);
        midnight.setConsumed(offer.group, amount, offer.maker);
    }
}
