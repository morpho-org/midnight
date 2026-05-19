// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {TickLib, LN_ONE_PLUS_DELTA, MAX_TICK} from "../../src/libraries/TickLib.sol";

contract TickLibWrapper {
    function maxTick() external pure returns (uint256) {
        return MAX_TICK;
    }

    function wExp(int256 x) external pure returns (uint256) {
        return TickLib.wExp(x);
    }

    function wExpAtTick(uint256 tick) external pure returns (uint256) {
        require(tick <= MAX_TICK, TickLib.TickOutOfRange());
        // forge-lint: disable-next-line(unsafe-typecast) as tick <= MAX_TICK < type(int256).max.
        int256 signedTick = int256(tick);
        // forge-lint: disable-next-line(unsafe-typecast) as MAX_TICK / 2 < type(int256).max.
        int256 halfMaxTick = int256(MAX_TICK / 2);
        return TickLib.wExp(LN_ONE_PLUS_DELTA * (halfMaxTick - signedTick));
    }

    function tickToPrice(uint256 tick) external pure returns (uint256) {
        return TickLib.tickToPrice(tick);
    }

    function priceToTick(uint256 price, uint256 spacing) external pure returns (uint256) {
        return TickLib.priceToTick(price, spacing);
    }
}
