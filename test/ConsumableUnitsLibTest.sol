// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {ConsumableUnitsLib} from "../src/periphery/ConsumableUnitsLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

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

        offer.market = market;
        offer.maker = borrower;
        offer.group = keccak256("consumable group");
        offer.tick = 4000;
        offer.maxUnits = 100e18;
    }

    function testMaxUnitsReturnsRemainingUnits() public {
        _setConsumed(40e18);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), 60e18);
    }

    function testMaxUnitsFloorsAtZeroWhenConsumedAboveCap() public {
        _setConsumed(125e18);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), 0);
    }

    function testMaxAssetsBuyReturnsUnitsForRemainingBuyerAssets() public {
        uint128 maxAssets = 1_000e18;
        uint128 consumed = 250e18;
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = 0;
        offer.maxAssets = maxAssets;

        _setConsumed(consumed);

        uint256 remainingAssets = uint256(maxAssets) - consumed;
        uint256 expectedUnits = remainingAssets.mulDivUp(WAD, TickLib.tickToPrice(offer.tick));

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
    }

    function testMaxAssetsSellReturnsUnitsForRemainingSellerAssets() public {
        uint128 maxAssets = 1_000e18;
        uint128 consumed = 250e18;
        offer.maxUnits = 0;
        offer.maxAssets = maxAssets;

        _setConsumed(consumed);

        uint256 remainingAssets = uint256(maxAssets) - consumed;
        uint256 expectedUnits = remainingAssets.mulDivDown(WAD, TickLib.tickToPrice(offer.tick));

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), expectedUnits);
    }

    function testMaxAssetsFloorsAtZeroWhenConsumedAboveCap() public {
        offer.maxUnits = 0;
        offer.maxAssets = 100e18;

        _setConsumed(125e18);

        assertEq(ConsumableUnitsLib.consumableUnits(address(midnight), id, offer), 0);
    }

    function _setConsumed(uint128 amount) internal {
        vm.prank(offer.maker);
        midnight.setConsumed(offer.group, amount, offer.maker);
    }
}
