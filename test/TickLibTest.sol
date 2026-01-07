// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {TickLib, MIN_TICK, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract TickLibTest is Test {
    function testExhaustiveTickToRoi() public pure {
        for (int256 t = MIN_TICK; t <= MAX_TICK; t++) {
            assertEq(TickLib.roiToTick(TickLib.tickToRoi(t)), t);
            assertLt(TickLib.tickToRoi(t), TickLib.tickToRoi(t + 1));
        }
    }

    function testSomeTicks() public pure {
        assertEq(TickLib.tickToPrice(MIN_TICK), 1e18);
        assertEq(TickLib.tickToPrice(0), WAD / 2);
        assertEq(TickLib.tickToPrice(MAX_TICK), 0);
    }

    function testRoiToTickSecondBestAtWorst(uint256 r) public pure {
        r = bound(r, TickLib.tickToRoi(MIN_TICK), TickLib.tickToRoi(MAX_TICK));
        int256 tr = TickLib.roiToTick(r);
        uint256 rtr = TickLib.tickToRoi(tr);
        uint256 rtrPrev = tr > MIN_TICK ? TickLib.tickToRoi(tr - 1) : rtr;
        uint256 rtrNext = tr < MAX_TICK ? TickLib.tickToRoi(tr + 1) : rtr;
        assertTrue((rtrPrev <= r && r <= rtr) || (rtr <= r && r <= rtrNext), "bound not tight");
    }

    function testRoiToTickInterpolationTight() public pure {
        for (int256 t = MIN_TICK; t < MAX_TICK; t++) {
            uint256 rt = TickLib.tickToRoi(t);
            uint256 rtp1 = TickLib.tickToRoi(t + 1);
            uint256 roiLow = rt + (rtp1 - rt) * 47 / 100;
            uint256 roiHigh = rt + (rtp1 - rt) * 55 / 100;

            assertEq(TickLib.roiToTick(roiLow), t, "47% interpolation should map to t");
            assertEq(TickLib.roiToTick(roiHigh), t + 1, "55% interpolation should map to t+1");
        }
    }
}
