// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract TickLibTest is Test {
    using UtilsLib for uint256;

    function testSomeTicks() public pure {
        assertEq(TickLib.tickToPrice(0), 0);
        assertEq(TickLib.tickToPrice(MAX_TICK / 2), WAD / 2);
        assertEq(TickLib.tickToPrice(MAX_TICK), 1e18);
    }

    function testSomePrices() public pure {
        (uint256 p, uint256 t) = TickLib.priceToTickAlignedPriceAndTick(0);
        assertEq(p, 0);
        assertEq(t, 0);
        (p, t) = TickLib.priceToTickAlignedPriceAndTick(WAD / 2);
        assertEq(p, WAD / 2);
        assertEq(t, MAX_TICK / 2);
        (p, t) = TickLib.priceToTickAlignedPriceAndTick(WAD);
        assertEq(p, WAD);
        assertEq(t, MAX_TICK);
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

    function testpriceToTickAlignedPriceAndTickEdges() public pure {
        // When exactly between 2 prices match the higher one.
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            uint256 price = TickLib.tickToPrice(tick);
            if (tick < MAX_TICK) {
                uint256 nextPrice = TickLib.tickToPrice(tick + 1);
                if (price != nextPrice) {
                    uint256 edgePrice = price + (nextPrice - price - 1) / 2;
                    (uint256 alignedEdgePrice,) = TickLib.priceToTickAlignedPriceAndTick(edgePrice);
                    assertEq(alignedEdgePrice, price, "lower price up to same distance");
                }
            }
            if (tick > 0) {
                uint256 prevPrice = TickLib.tickToPrice(tick - 1);
                if (price != prevPrice) {
                    uint256 edgePrice = price - (price - prevPrice) / 2;
                    (uint256 alignedEdgePrice,) = TickLib.priceToTickAlignedPriceAndTick(edgePrice);
                    assertEq(alignedEdgePrice, price, "higher price not matching");
                }
            }
        }
    }
}
