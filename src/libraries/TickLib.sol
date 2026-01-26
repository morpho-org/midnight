// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "./ConstantsLib.sol";

// Min and max useful ticks.
// Without the PRICE_STEP rounding, the tick range is -1679 for price 1 to 1679 for price 0.
int256 constant MIN_TICK = -495;
int256 constant MAX_TICK = 495;
// ln(1.025) * 1e18
int256 constant LN_1_025_WAD = 24692612590371416;
// ln(2) * 1e18
int256 constant LN2_WAD = 693147180559945344;
int256 constant WAD_INT = 1e18;
// x96 unit
uint256 constant X96 = 1 << 96;
// (1/log2(1.025))x96
int256 constant INV_LOG2_1_025_X96 = 2224016485364590939422807110544;
uint256 constant PRICE_STEP = 1e13;

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
            // forge-lint: disable-next-item(divide-before-multiply) loss is the point
            return ((price + PRICE_STEP / 2) / PRICE_STEP) * PRICE_STEP;
        }
    }

    /// @dev Returns the closest tick-aligned price and a tick of this price.
    /// @dev If there are two equally close prices, the higher one is returned.
    function priceToTickAndTickAlignedPrice(uint256 price) internal pure returns (int256 tick, uint256 alignedPrice) {
        unchecked {
            if (price == 0) return (MAX_TICK, tickToPrice(MAX_TICK));
            if (price >= WAD) return (MIN_TICK, tickToPrice(MIN_TICK));

            tick = roiToTick(((WAD - price) << 96) / price);
            alignedPrice = tickToPrice(tick);

            if (alignedPrice > price && tick < MAX_TICK) {
                uint256 nextAlignedPrice = tickToPrice(tick + 1);
                if (2 * price < alignedPrice + nextAlignedPrice) {
                    return (tick + 1, nextAlignedPrice);
                }
            } else if (alignedPrice < price && tick > MIN_TICK) {
                uint256 prevAlignedPrice = tickToPrice(tick - 1);
                if (2 * price >= alignedPrice + prevAlignedPrice) {
                    return (tick - 1, prevAlignedPrice);
                }
            }
            return (tick, alignedPrice);
        }
    }

    function roiToTick(uint256 roi) internal pure returns (int256) {
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
        int256 log2roiX6 = (int256(msb) - 96) << 6;

        assembly ("memory-safe") {
            mpow := shr(127, mul(mpow, mpow))
            let highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, shl(5, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, shl(4, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, shl(3, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, shl(2, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, shl(1, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX6 := or(log2roiX6, highbit)
        }

        return (log2roiX6 * INV_LOG2_1_025_X96 + (1 << 101)) >> 102;
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
