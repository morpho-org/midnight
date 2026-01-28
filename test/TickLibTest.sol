// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {TickLib} from "../src/libraries/TickLib.sol";
import {MIN_TICK, MAX_TICK} from "../src/libraries/ConstantsLib.sol";
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

    function testPriceToTickRoundtrip() public pure {
        for (int256 t = MIN_TICK; t <= MAX_TICK; t++) {
            uint256 price = TickLib.tickToPrice(t);
            (, int256 tick) = TickLib.priceToTickAlignedPriceAndTick(price);
            assertEq(tick, t, "roundtrip failed");
        }
    }

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, WAD);
        (uint256 alignedPrice, int256 tick) = TickLib.priceToTickAlignedPriceAndTick(price);

        assertEq(alignedPrice, TickLib.tickToPrice(tick), "aligned price mismatch");
        assertGe(tick, MIN_TICK, "tick below min");
        assertLe(tick, MAX_TICK, "tick above max");

        uint256 prevPrice = tick > MIN_TICK ? TickLib.tickToPrice(tick - 1) : type(uint256).max;
        uint256 nextPrice = tick < MAX_TICK ? TickLib.tickToPrice(tick + 1) : 0;
        uint256 distToAligned = alignedPrice > price ? alignedPrice - price : price - alignedPrice;

        if (tick > MIN_TICK) {
            uint256 distToPrev = prevPrice - price;
            assertLt(distToAligned, distToPrev, "not strictly closer than to prev");
        }
        if (tick < MAX_TICK) {
            uint256 distToNext = price - nextPrice;
            assertLe(distToAligned, distToNext, "not closer than to next");
        }
    }
}
