// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {AccessibleTickLib, MAX_LEVEL, BASE_SPACING} from "../src/libraries/AccessibleTickLib.sol";

contract AccessibleTickLibTest is Test {
    // Spacing

    function testSpacing() public pure {
        assertEq(AccessibleTickLib.spacing(0), 8);
        assertEq(AccessibleTickLib.spacing(1), 4);
        assertEq(AccessibleTickLib.spacing(2), 2);
        assertEq(AccessibleTickLib.spacing(3), 1);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSpacingOutOfRange(uint256 level) public {
        level = bound(level, MAX_LEVEL + 1, type(uint256).max);
        vm.expectRevert("level out of range");
        AccessibleTickLib.spacing(level);
    }

    // Boundary tick alignment

    function testBoundaryTicksAccessibleAtAllLevels() public pure {
        for (uint256 level = 0; level <= MAX_LEVEL; level++) {
            assertTrue(AccessibleTickLib.isAccessible(0, level), "tick 0 should be accessible at all levels");
            assertTrue(
                AccessibleTickLib.isAccessible(MAX_TICK, level), "MAX_TICK should be accessible at all levels"
            );
        }
    }

    // Accessibility at each level

    function testLevel0OnlyMultiplesOf8() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            assertEq(AccessibleTickLib.isAccessible(tick, 0), tick % 8 == 0);
        }
    }

    function testLevel1OnlyMultiplesOf4() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            assertEq(AccessibleTickLib.isAccessible(tick, 1), tick % 4 == 0);
        }
    }

    function testLevel2OnlyMultiplesOf2() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            assertEq(AccessibleTickLib.isAccessible(tick, 2), tick % 2 == 0);
        }
    }

    function testLevel3EveryTick() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            assertTrue(AccessibleTickLib.isAccessible(tick, 3));
        }
    }

    // Monotonic refinement: finer levels include all coarser ticks

    function testMonotonicRefinement() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            for (uint256 level = 0; level < MAX_LEVEL; level++) {
                if (AccessibleTickLib.isAccessible(tick, level)) {
                    assertTrue(
                        AccessibleTickLib.isAccessible(tick, level + 1),
                        "finer level must include all coarser ticks"
                    );
                }
            }
        }
    }

    function testMonotonicRefinementFuzz(uint256 tick, uint256 coarseLevel) public pure {
        tick = bound(tick, 0, MAX_TICK);
        coarseLevel = bound(coarseLevel, 0, MAX_LEVEL - 1);
        if (AccessibleTickLib.isAccessible(tick, coarseLevel)) {
            for (uint256 finerLevel = coarseLevel + 1; finerLevel <= MAX_LEVEL; finerLevel++) {
                assertTrue(
                    AccessibleTickLib.isAccessible(tick, finerLevel),
                    "tick accessible at coarse level must be accessible at all finer levels"
                );
            }
        }
    }

    // Accessible tick counts per level

    function testAccessibleTickCounts() public pure {
        uint256[4] memory counts;
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            for (uint256 level = 0; level <= MAX_LEVEL; level++) {
                if (AccessibleTickLib.isAccessible(tick, level)) counts[level]++;
            }
        }
        assertEq(counts[0], MAX_TICK / 8 + 1, "level 0 count");
        assertEq(counts[1], MAX_TICK / 4 + 1, "level 1 count");
        assertEq(counts[2], MAX_TICK / 2 + 1, "level 2 count");
        assertEq(counts[3], MAX_TICK + 1, "level 3 count");
    }

    // Projection down

    function testProjectDownAlreadyAccessible(uint256 tick, uint256 level) public pure {
        tick = bound(tick, 0, MAX_TICK);
        level = bound(level, 0, MAX_LEVEL);
        if (AccessibleTickLib.isAccessible(tick, level)) {
            assertEq(AccessibleTickLib.projectDown(tick, level), tick);
        }
    }

    function testProjectDownResult(uint256 tick, uint256 level) public pure {
        tick = bound(tick, 0, MAX_TICK);
        level = bound(level, 0, MAX_LEVEL);
        uint256 projected = AccessibleTickLib.projectDown(tick, level);
        assertTrue(AccessibleTickLib.isAccessible(projected, level), "projected tick must be accessible");
        assertLe(projected, tick, "projected tick must be <= original");
        uint256 s = AccessibleTickLib.spacing(level);
        if (projected + s <= MAX_TICK) {
            assertGt(projected + s, tick, "next accessible tick must be > original");
        }
    }

    // Projection up

    function testProjectUpAlreadyAccessible(uint256 tick, uint256 level) public pure {
        tick = bound(tick, 0, MAX_TICK);
        level = bound(level, 0, MAX_LEVEL);
        if (AccessibleTickLib.isAccessible(tick, level)) {
            assertEq(AccessibleTickLib.projectUp(tick, level), tick);
        }
    }

    function testProjectUpResult(uint256 tick, uint256 level) public pure {
        tick = bound(tick, 0, MAX_TICK);
        level = bound(level, 0, MAX_LEVEL);
        uint256 projected = AccessibleTickLib.projectUp(tick, level);
        assertTrue(projected <= MAX_TICK, "projected tick must be <= MAX_TICK");
        assertTrue(AccessibleTickLib.isAccessible(projected, level), "projected tick must be accessible");
        assertGe(projected, tick, "projected tick must be >= original");
        uint256 s = AccessibleTickLib.spacing(level);
        if (projected >= s) {
            assertLt(projected - s, tick, "previous accessible tick must be < original");
        }
    }

    function testProjectUpCappedAtMaxTick() public pure {
        uint256 projected = AccessibleTickLib.projectUp(MAX_TICK, 0);
        assertEq(projected, MAX_TICK, "projectUp(MAX_TICK, 0) should be MAX_TICK");
    }

    // Out-of-range tick reverts

    /// forge-config: default.allow_internal_expect_revert = true
    function testIsAccessibleOutOfRange(uint256 tick, uint256 level) public {
        tick = bound(tick, MAX_TICK + 1, type(uint256).max);
        level = bound(level, 0, MAX_LEVEL);
        vm.expectRevert("tick out of range");
        AccessibleTickLib.isAccessible(tick, level);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testProjectDownOutOfRange(uint256 tick, uint256 level) public {
        tick = bound(tick, MAX_TICK + 1, type(uint256).max);
        level = bound(level, 0, MAX_LEVEL);
        vm.expectRevert("tick out of range");
        AccessibleTickLib.projectDown(tick, level);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testProjectUpOutOfRange(uint256 tick, uint256 level) public {
        tick = bound(tick, MAX_TICK + 1, type(uint256).max);
        level = bound(level, 0, MAX_LEVEL);
        vm.expectRevert("tick out of range");
        AccessibleTickLib.projectUp(tick, level);
    }

    // Projection consistency: projectDown <= tick <= projectUp

    function testProjectConsistency(uint256 tick, uint256 level) public pure {
        tick = bound(tick, 0, MAX_TICK);
        level = bound(level, 0, MAX_LEVEL);
        uint256 down = AccessibleTickLib.projectDown(tick, level);
        uint256 up = AccessibleTickLib.projectUp(tick, level);
        assertLe(down, tick);
        assertGe(up, tick);
        assertLe(down, up);
    }
}
