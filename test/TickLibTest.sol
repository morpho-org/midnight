// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract TickLibTest is Test {
    using UtilsLib for uint256;

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

    function testReturnJumps() public pure {
        for (uint256 i = 207; i <= 729; i++) {
            uint256 previousReturn = _return(TickLib.tickToPrice(i - 1));
            uint256 currentReturn = _return(TickLib.tickToPrice(i));
            assertApproxEqRel(
                currentReturn.mulDivDown(1e18, previousReturn), 1.025e18, 0.1e18, string.concat("tick ", vm.toString(i))
            );
        }
    }

    function _return(uint256 price) internal pure returns (uint256) {
        return uint256(1e18).mulDivDown(1e18, price) - 1e18;
    }

    function testPriceToTickRoundtrip() public pure {
        for (uint256 t = 0; t <= MAX_TICK; t++) {
            uint256 price = TickLib.tickToPrice(t);
            uint256 tick = TickLib.priceToTick(price);
            assertEq(tick, t, "roundtrip failed");
        }
    }

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, WAD);
        uint256 tick = TickLib.priceToTick(price);
        uint256 alignedPrice = TickLib.tickToPrice(tick);

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
