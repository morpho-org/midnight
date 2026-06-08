// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, stdError} from "../lib/forge-std/src/Test.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {LN_ONE_PLUS_DELTA, MAX_TICK, TickLib} from "../src/libraries/TickLib.sol";
import {
    WAD,
    LIQUIDATION_CURSOR_LOW,
    LIQUIDATION_CURSOR_HIGH,
    LLTV_0,
    LLTV_1,
    LLTV_2,
    LLTV_3,
    LLTV_4,
    LLTV_5,
    LLTV_6,
    LLTV_7,
    maxLif
} from "../src/libraries/ConstantsLib.sol";

contract UtilsLibTest is Test {
    int256 internal constant WEXP_LN2 = 0.693147180559945309e18;
    int256 internal constant WEXP_OFFSET = 0.32261121498945987e18;
    int256 internal constant WEXP_MONOTONICITY_STEP = 1e14;
    int256 internal constant WEXP_MONOTONICITY_WINDOW = 32;

    function testFuzzCountBits(uint128 bitmap) public pure {
        uint256 actual = UtilsLib.countBits(bitmap);
        uint256 expected;
        uint128 temp = bitmap;
        while (temp != 0) {
            temp &= temp - 1;
            expected++;
        }
        assertEq(actual, expected);
    }

    function testMin(uint256 a, uint256 b) public pure {
        assertEq(UtilsLib.min(a, b), a < b ? a : b);
    }

    function testZeroFloorSub(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.zeroFloorSub(x, y), x > y ? x - y : 0);
    }

    function testMulDivDown(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        if (x > 0) y = bound(y, 0, type(uint256).max / x);

        assertEq(UtilsLib.mulDivDown(x, y, d), (x * y) / d, "mulDivDown result mismatch");
    }

    function testMulDivDownDivisionByZero(uint256 x, uint256 y) public {
        if (x > 0) y = bound(y, 0, type(uint256).max / x);

        vm.expectRevert(stdError.divisionError);
        this.mulDivDown(x, y, 0);
    }

    function testMulDivDownOverflow(uint256 x, uint256 y, uint256 d) public {
        x = bound(x, 2, type(uint256).max);
        y = bound(y, type(uint256).max / x + 1, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        this.mulDivDown(x, y, d);
    }

    function testMulDivUp(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        if (x > 0) y = bound(y, 0, (type(uint256).max - (d - 1)) / x);

        assertEq(UtilsLib.mulDivUp(x, y, d), (x * y + (d - 1)) / d, "mulDivUp result mismatch");
    }

    function testMulDivUpDivisionByZero(uint256 x, uint256 y) public {
        // because there is d-1.
        vm.expectRevert(stdError.arithmeticError);
        this.mulDivUp(x, y, 0);
    }

    function testMulDivUpOverflow(uint256 x, uint256 y, uint256 d) public {
        d = bound(d, 1, type(uint256).max);
        x = bound(x, 1, type(uint256).max);
        vm.assume(!(d == 1 && x == 1)); // covered by testMulDivUp.
        y = bound(y, (type(uint256).max - (d - 1)) / x + 1, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        this.mulDivUp(x, y, d);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testToUint128Overflow(uint256 x) public {
        x = bound(x, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.expectRevert(UtilsLib.CastOverflow.selector);
        UtilsLib.toUint128(x);
    }

    function mulDivDown(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivDown(x, y, d);
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivUp(x, y, d);
    }

    function testWExpNonDecreasing() public pure {
        int256 start = -WEXP_OFFSET;
        int256 end = WEXP_LN2 / 2 - WEXP_OFFSET - 1;

        // Keep the range scan tractable, then pin one-wei windows around the requested points.
        _assertWExpNonDecreasing(start, end, WEXP_MONOTONICITY_STEP);
        _assertWExpNonDecreasingAround(start);
        _assertWExpNonDecreasingAround(end);

        // Also pin the old and new range-reduction boundaries, where jumps are most likely.
        _assertWExpNonDecreasingAround(WEXP_LN2 / 2 - 1);
        _assertWExpNonDecreasingAround(WEXP_LN2 - WEXP_OFFSET - 1);
    }

    function testWExpIncreasingAtTicks() public pure {
        // MAX_TICK is a small constant, so casting it to int256 is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 previous = TickLib.wExp(LN_ONE_PLUS_DELTA * (int256(MAX_TICK / 2) - int256(MAX_TICK)));
        for (uint256 tick = MAX_TICK; tick > 0; tick--) {
            // tick - 1 is bounded by MAX_TICK - 1, so casting it to int256 is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 current = TickLib.wExp(LN_ONE_PLUS_DELTA * (int256(MAX_TICK / 2) - int256(tick - 1)));
            assertGt(current, previous);
            previous = current;
        }
    }

    function _assertWExpNonDecreasing(int256 start, int256 end, int256 step) internal pure {
        uint256 previous = TickLib.wExp(start);
        for (int256 x = start + step; x < end; x += step) {
            uint256 current = TickLib.wExp(x);
            assertGe(current, previous);
            previous = current;
        }
        assertGe(TickLib.wExp(end), previous);
    }

    function _assertWExpNonDecreasingAround(int256 center) internal pure {
        int256 start = center - WEXP_MONOTONICITY_WINDOW;
        uint256 previous = TickLib.wExp(start);
        for (int256 i = 1; i <= 2 * WEXP_MONOTONICITY_WINDOW + 1; i++) {
            uint256 current = TickLib.wExp(start + i);
            assertGe(current, previous);
            previous = current;
        }
    }

    function testWExp() public pure {
        assertApproxEqRel(TickLib.wExp(-20 ether), 0.000000002061153622 ether, 0.001 ether, "exp(-20)");
        assertApproxEqRel(TickLib.wExp(-19 ether), 0.000000005602796438 ether, 0.001 ether, "exp(-19)");
        assertApproxEqRel(TickLib.wExp(-18 ether), 0.000000015229979745 ether, 0.001 ether, "exp(-18)");
        assertApproxEqRel(TickLib.wExp(-17 ether), 0.000000041399377188 ether, 0.001 ether, "exp(-17)");
        assertApproxEqRel(TickLib.wExp(-16 ether), 0.000000112535174719 ether, 0.001 ether, "exp(-16)");
        assertApproxEqRel(TickLib.wExp(-15 ether), 0.000000305902320502 ether, 0.001 ether, "exp(-15)");
        assertApproxEqRel(TickLib.wExp(-14 ether), 0.000000831528719104 ether, 0.001 ether, "exp(-14)");
        assertApproxEqRel(TickLib.wExp(-13 ether), 0.000002260329406981 ether, 0.001 ether, "exp(-13)");
        assertApproxEqRel(TickLib.wExp(-12 ether), 0.000006144212353328 ether, 0.001 ether, "exp(-12)");
        assertApproxEqRel(TickLib.wExp(-11 ether), 0.000016701700790246 ether, 0.001 ether, "exp(-11)");
        assertApproxEqRel(TickLib.wExp(-10 ether), 0.000045399929762485 ether, 0.001 ether, "exp(-10)");
        assertApproxEqRel(TickLib.wExp(-9 ether), 0.00012340980408668 ether, 0.001 ether, "exp(-9)");
        assertApproxEqRel(TickLib.wExp(-8 ether), 0.000335462627902512 ether, 0.001 ether, "exp(-8)");
        assertApproxEqRel(TickLib.wExp(-7 ether), 0.000911881965554516 ether, 0.001 ether, "exp(-7)");
        assertApproxEqRel(TickLib.wExp(-6 ether), 0.002478752176666359 ether, 0.001 ether, "exp(-6)");
        assertApproxEqRel(TickLib.wExp(-5 ether), 0.006737946999085467 ether, 0.001 ether, "exp(-5)");
        assertApproxEqRel(TickLib.wExp(-4 ether), 0.01831563888873418 ether, 0.001 ether, "exp(-4)");
        assertApproxEqRel(TickLib.wExp(-3 ether), 0.049787068367863944 ether, 0.001 ether, "exp(-3)");
        assertApproxEqRel(TickLib.wExp(-2 ether), 0.135335283236612692 ether, 0.001 ether, "exp(-2)");
        assertApproxEqRel(TickLib.wExp(-1 ether), 0.367879441171442322 ether, 0.001 ether, "exp(-1)");
        assertEq(TickLib.wExp(0 ether), 1 ether, "exp(0)");
        assertApproxEqRel(TickLib.wExp(1 ether), 2.718281828459045235 ether, 0.001 ether, "exp(1)");
        assertApproxEqRel(TickLib.wExp(2 ether), 7.389056098930649644 ether, 0.001 ether, "exp(2)");
        assertApproxEqRel(TickLib.wExp(3 ether), 20.085536923187667741 ether, 0.001 ether, "exp(3)");
        assertApproxEqRel(TickLib.wExp(4 ether), 54.59815003314423616 ether, 0.001 ether, "exp(4)");
        assertApproxEqRel(TickLib.wExp(5 ether), 148.413159102576603421 ether, 0.001 ether, "exp(5)");
        assertApproxEqRel(TickLib.wExp(6 ether), 403.428793492735122608 ether, 0.001 ether, "exp(6)");
        assertApproxEqRel(TickLib.wExp(7 ether), 1096.633158428458599264 ether, 0.001 ether, "exp(7)");
        assertApproxEqRel(TickLib.wExp(8 ether), 2980.957987041728274743 ether, 0.001 ether, "exp(8)");
        assertApproxEqRel(TickLib.wExp(9 ether), 8103.083927575384008296 ether, 0.001 ether, "exp(9)");
        assertApproxEqRel(TickLib.wExp(10 ether), 22026.465794806716516958 ether, 0.001 ether, "exp(10)");
        assertApproxEqRel(TickLib.wExp(11 ether), 59874.141715197818455327 ether, 0.001 ether, "exp(11)");
        assertApproxEqRel(TickLib.wExp(12 ether), 162754.791419003920505928 ether, 0.001 ether, "exp(12)");
        assertApproxEqRel(TickLib.wExp(13 ether), 442413.39200892047204928 ether, 0.001 ether, "exp(13)");
        assertApproxEqRel(TickLib.wExp(14 ether), 1202604.284164776777749504 ether, 0.001 ether, "exp(14)");
        assertApproxEqRel(TickLib.wExp(15 ether), 3269017.372472110789246976 ether, 0.001 ether, "exp(15)");
        assertApproxEqRel(TickLib.wExp(16 ether), 8886110.52050787263668224 ether, 0.001 ether, "exp(16)");
        assertApproxEqRel(TickLib.wExp(17 ether), 24154952.75366849249681408 ether, 0.001 ether, "exp(17)");
        assertApproxEqRel(TickLib.wExp(18 ether), 65659969.137330511139838976 ether, 0.001 ether, "exp(18)");
        assertApproxEqRel(TickLib.wExp(19 ether), 178482300.96318726092869632 ether, 0.001 ether, "exp(19)");
        assertApproxEqRel(TickLib.wExp(20 ether), 485165195.409790277969936384 ether, 0.001 ether, "exp(20)");
    }

    // This test makes sure that the computation of maxRepaid (for RCF) is not too imprecise.
    function testRcfBound() public pure {
        uint256[8] memory lltvs = [LLTV_0, LLTV_1, LLTV_2, LLTV_3, LLTV_4, LLTV_5, LLTV_6, LLTV_7];
        uint256[2] memory cursors = [LIQUIDATION_CURSOR_LOW, LIQUIDATION_CURSOR_HIGH];
        for (uint256 i = 0; i < lltvs.length; i++) {
            uint256 lltv = lltvs[i];
            for (uint256 j = 0; j < cursors.length; j++) {
                uint256 lif = maxLif(lltv, cursors[j]);
                assertLt(lif * lltv, WAD * WAD);
                assertLt(WAD * WAD / (WAD * WAD - lif * lltv), 100);
            }
        }
        // Also ensure that the bound is close to the max bound.
        uint256 lifHigh7 = maxLif(LLTV_7, LIQUIDATION_CURSOR_HIGH);
        assertGt(WAD * WAD / (WAD * WAD - lifHigh7 * LLTV_7), 90);
    }
}
