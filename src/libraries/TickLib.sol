// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "./ConstantsLib.sol";

// Min and max useful ticks.
// Without the PRICE_PRECISION rounding, if we round up the price for negative ticks and round it down for positive
// ticks, the range is -1679 (price is 1) to 1679 (price is 0). 1 is reached naturally by rounding at -1679
// -1 is reached naturally by rounding at 1679
int256 constant MIN_TICK = -588;
int256 constant MAX_TICK = 588;
// ln(1.025) * 1e18
int256 constant LN_1_025_WAD = 24692612590371416;
// ln(2) * 1e18
int256 constant LN2_WAD = 693147180559945344;
int256 constant WAD_INT = 1e18;
// x96 unit (still needed for roiToTick)
uint256 constant X96 = 1 << 96;
// (1/log2(1.025))x96
int256 constant INV_LOG2_1_025_X96 = 2224016485364590939422807110544;

uint256 constant PRICE_PRECISION = 1e12;

library TickLib {
    function tickToPrice(int256 tick) internal pure returns (uint256) {
        unchecked {
            int256 x = LN_1_025_WAD * tick;
            uint256 price;
            if (tick >= 0) {
                // forge-lint: disable-next-item(unsafe-typecast) x is positive
                uint256 expWad = wExp(uint256(x));
                price = WAD * WAD / (WAD + expWad);
            } else {
                // forge-lint: disable-next-item(unsafe-typecast) x is negative
                uint256 expWad = wExp(uint256(-x));
                price = expWad * WAD / (WAD + expWad);
            }
            return ((price + PRICE_PRECISION / 2) / PRICE_PRECISION) * PRICE_PRECISION;
        }
    }

    function priceToTick(uint256 price) internal pure returns (int256) {
        if (price == 0) return MAX_TICK;
        int256 tickOfRoi = roiToTick(((1e18 - price) << 96) / price);
        if (tickOfRoi <= MIN_TICK) return MIN_TICK;
        if (tickOfRoi >= MAX_TICK) return MAX_TICK;
        return tickOfRoi;
    }

    function roiToTick(uint256 roi) internal pure returns (int256) {
        if (roi == 0) return MIN_TICK;
        uint256 msb;
        assembly {
            msb := sub(255, clz(roi))
        }

        uint256 mpow;
        if (msb >= 128) {
            mpow = roi >> (msb - 127);
        } else {
            mpow = roi << (127 - msb);
        }

        // forge-lint: disable-next-item(unsafe-typecast) msb is a bit position
        int256 log2roiX10 = (int256(msb) - 96) << 10;

        assembly ("memory-safe") {
            mpow := shr(127, mul(mpow, mpow))
            let highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(9, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(8, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(7, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(6, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(5, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(4, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(3, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(2, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, shl(1, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX10 := or(log2roiX10, highbit)
        }

        return (log2roiX10 * INV_LOG2_1_025_X96 + (1 << 105)) >> 106;
    }

    function wExp(uint256 x) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast) x should be small
            int256 q = (int256(x) + LN2_WAD / 2) / LN2_WAD;
            // forge-lint: disable-next-item(unsafe-typecast) x should be small
            int256 r = int256(x) - q * LN2_WAD;
            int256 secondTerm = (r * r) / (2 * WAD_INT);
            int256 thirdTerm = (secondTerm * r) / (3 * WAD_INT);
            int256 expR = WAD_INT + r + secondTerm + thirdTerm;
            // forge-lint: disable-next-line(unsafe-typecast) e^r positive, q positive
            return uint256(expR) << uint256(q);
        }
    }
}
