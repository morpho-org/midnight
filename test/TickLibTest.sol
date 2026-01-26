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

    function testPriceToTickAndTickAlignedPrice() public pure {
        for (uint256 price = 0; price < WAD; price += PRICE_STEP) {
            (int256 t, uint256 alignedPrice) = TickLib.priceToTickAndTickAlignedPrice(price);

            if (t > MIN_TICK) {
                uint256 prevAlignedPrice = TickLib.tickToPrice(t - 1);
                assertLe(dist(alignedPrice, price), dist(prevAlignedPrice, price), "closer to prev");
            }

            if (t < MAX_TICK) {
                uint256 nextAlignedPrice = TickLib.tickToPrice(t + 1);
                assertLe(dist(alignedPrice, price), dist(nextAlignedPrice, price), "closer to next");
            }
        }
    }

    function dist(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x - y : y - x;
    }
}
