// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {TickLib, MIN_TICK, MAX_TICK} from "../src/libraries/TickLib.sol";
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

    function testPriceToTickEdgeCases() public pure {
        assertEq(TickLib.priceToTick(1e18), MIN_TICK);
        assertEq(TickLib.priceToTick(0), MAX_TICK);
    }

    function testPricePreservedAfterRoundtrip() public pure {
        for (int256 t = MIN_TICK; t <= MAX_TICK; t++) {
            uint256 price = TickLib.tickToPrice(t);
            uint256 priceAfterRoundtrip = TickLib.tickToPrice(TickLib.priceToTick(price));
            assertEq(priceAfterRoundtrip, price, "P(t) should equal P(T(P(t)))");
        }
    }
}
