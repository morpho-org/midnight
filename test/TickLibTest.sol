// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {TickLib, MIN_TICK, MAX_TICK, PRICE_STEP} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract TickLibTest is Test {
    function testSomeTicks() public pure {
        assertEq(TickLib.tickToPrice(MIN_TICK), 1e18);
        assertEq(TickLib.tickToPrice(0), WAD / 2);
        assertEq(TickLib.tickToPrice(MAX_TICK), 0);
    }

    function testTickToPriceMonotone() public pure {
        for (int256 t = MIN_TICK; t < MAX_TICK; t++) {
            assertGe(TickLib.tickToPrice(t), TickLib.tickToPrice(t + 1), "price should be monotonically decreasing");
        }
    }

    function testPriceToTickAndTickAlignedPriceEdges() public pure {
        // When exactly between 2 prices match the higher one.
        for (int256 tick = MIN_TICK; tick <= MAX_TICK; tick++) {
            uint256 price = TickLib.tickToPrice(tick);
            if (tick < MAX_TICK) {
                uint256 nextPrice = TickLib.tickToPrice(tick + 1);
                if (price != nextPrice) {
                    uint256 edgePrice = price - (price - nextPrice) / 2;
                    (, uint256 alignedEdgePrice) = TickLib.priceToTickAndTickAlignedPrice(edgePrice);
                    assertEq(alignedEdgePrice, price, "lower price up to same distance");
                }
            }
            if (tick > MIN_TICK) {
                uint256 prevPrice = TickLib.tickToPrice(tick - 1);
                if (price != prevPrice) {
                    uint256 edgePrice = price + (prevPrice - price - 1) / 2;
                    (, uint256 alignedEdgePrice) = TickLib.priceToTickAndTickAlignedPrice(edgePrice);
                    assertEq(alignedEdgePrice, price, "higher price not matching");
                }
            }
        }
    }
}
