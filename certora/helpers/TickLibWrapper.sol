// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {TickLib, MAX_TICK} from "../../src/libraries/TickLib.sol";

contract TickLibWrapper {
    function maxTick() external pure returns (uint256) {
        return MAX_TICK;
    }

    function wExp(int256 x) external pure returns (uint256) {
        return TickLib.wExp(x);
    }

    function tickToPrice(uint256 tick) external pure returns (uint256) {
        return TickLib.tickToPrice(tick);
    }

    function priceToTick(uint256 price, uint256 spacing) external pure returns (uint256) {
        return TickLib.priceToTick(price, spacing);
    }
}
