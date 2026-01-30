// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract TickLibTest is Test {
    function testSomeTicks() public pure {
        assertEq(TickLib.tickToPrice(MAX_TICK), 1e18);
        assertEq(TickLib.tickToPrice(MAX_TICK / 2), WAD / 2);
        assertEq(TickLib.tickToPrice(0), 0);
    }

    function testTickToPriceMonotone() public pure {
        for (uint256 t = 0; t < MAX_TICK; t++) {
            assertLe(TickLib.tickToPrice(t), TickLib.tickToPrice(t + 1), "price should be monotonically increasing");
        }
    }

    function testPriceToTickRoundtrip() public pure {
        for (uint256 t = 0; t <= MAX_TICK; t++) {
            uint256 price = TickLib.tickToPrice(t);
            (, uint256 tick) = TickLib.priceToTickAlignedPriceAndTick(price);
            assertEq(tick, t, "roundtrip failed");
        }
    }

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, WAD);
        (uint256 alignedPrice, uint256 tick) = TickLib.priceToTickAlignedPriceAndTick(price);

        assertEq(alignedPrice, TickLib.tickToPrice(tick), "aligned price mismatch");
        assertGe(tick, 0, "tick below min");
        assertLe(tick, MAX_TICK, "tick above max");

        uint256 prevPrice = tick > 0 ? TickLib.tickToPrice(tick - 1) : 0;
        uint256 nextPrice = tick < MAX_TICK ? TickLib.tickToPrice(tick + 1) : type(uint256).max;
        uint256 distToAligned = alignedPrice > price ? alignedPrice - price : price - alignedPrice;

        if (tick > 0) {
            uint256 distToPrev = price - prevPrice;
            assertLe(distToAligned, distToPrev, "not closer than to prev");
        }
        if (tick < MAX_TICK) {
            uint256 distToNext = nextPrice - price;
            assertLt(distToAligned, distToNext, "not strictly closer than to next");
        }
    }
}
