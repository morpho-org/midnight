// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {TickLib, MAX_TICK, LN_ONE_PLUS_DELTA, PRICE_ROUNDING_STEP} from "../../src/libraries/TickLib.sol";

contract TickLibWrapper {
    function lnOnePlusDelta() external pure returns (int256) {
        return LN_ONE_PLUS_DELTA;
    }

    function maxTick() external pure returns (uint256) {
        return MAX_TICK;
    }

    function priceRoundingStep() external pure returns (uint256) {
        return PRICE_ROUNDING_STEP;
    }

    function wExp(int256 x) external pure returns (uint256) {
        return TickLib.wExp(x);
    }

    // Mirrors the expR Taylor series used inside TickLib.wExp for non-negative inputs.
    function expR(int256 x) external pure returns (int256) {
        unchecked {
            int256 ln2 = 0.693147180559945309e18;
            int256 offset = 0.32261121498945987e18;
            int256 q = (x + offset) / ln2;
            int256 r = x - q * ln2;
            int256 secondTerm = r * r / (2 * 1e18);
            int256 thirdTerm = secondTerm * r / (3 * 1e18);
            return 1e18 + r + secondTerm + thirdTerm;
        }
    }

    function tickToPrice(uint256 tick) external pure returns (uint256) {
        return TickLib.tickToPrice(tick);
    }

    function priceToTick(uint256 price, uint256 spacing) external pure returns (uint256) {
        return TickLib.priceToTick(price, spacing);
    }
}
