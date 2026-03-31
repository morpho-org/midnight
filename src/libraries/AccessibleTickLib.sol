// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_TICK} from "./TickLib.sol";

uint256 constant MAX_LEVEL = 3;
uint256 constant BASE_SPACING = 8;

library AccessibleTickLib {
    /// @dev Returns the tick spacing for a given accessibility level.
    /// Level 0 → 8, Level 1 → 4, Level 2 → 2, Level 3 → 1.
    function spacing(uint256 level) internal pure returns (uint256) {
        require(level <= MAX_LEVEL, "level out of range");
        return BASE_SPACING >> level;
    }

    /// @dev Returns true if `tick` is accessible at the given level.
    function isAccessible(uint256 tick, uint256 level) internal pure returns (bool) {
        require(tick <= MAX_TICK, "tick out of range");
        return tick % spacing(level) == 0;
    }

    /// @dev Rounds `tick` down to the nearest accessible tick at the given level.
    /// Intended for off-chain / periphery use (not called by the core protocol).
    function projectDown(uint256 tick, uint256 level) internal pure returns (uint256) {
        require(tick <= MAX_TICK, "tick out of range");
        uint256 s = spacing(level);
        // forge-lint: disable-next-line(divide-before-multiply)
        return (tick / s) * s;
    }

    /// @dev Rounds `tick` up to the nearest accessible tick at the given level, capped at MAX_TICK.
    /// Intended for off-chain / periphery use (not called by the core protocol).
    function projectUp(uint256 tick, uint256 level) internal pure returns (uint256) {
        require(tick <= MAX_TICK, "tick out of range");
        uint256 s = spacing(level);
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 projected = ((tick + s - 1) / s) * s;
        return projected > MAX_TICK ? MAX_TICK : projected;
    }
}
