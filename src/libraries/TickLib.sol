// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, MIN_TICK, MAX_TICK} from "./ConstantsLib.sol";

/// @dev Ticks are converted to/from log_1.025(roi) by MAX_TICK/2 - x.
// forge-lint: disable-next-item(unsafe-typecast) max tick small enough
int256 constant MAX_ROI_LOG = int256(MAX_TICK / 2);
int256 constant MIN_ROI_LOG = -MAX_ROI_LOG;
// ln(1.025) * 1e18
int256 constant LN_1_025_WAD = 24692612590371416;
// ln(2) * 1e18
int256 constant LN2_WAD = 693147180559945344;
int256 constant WAD_INT = 1e18;
// (1/log2(1.025))x96
int256 constant INV_LOG2_1_025_X96 = 2224016485364590939422807110544;
uint256 constant PRICE_STEP = 1e13;

library TickLib {
    /// @dev Converts a tick to a price.
    function tickToPrice(uint256 tick) internal pure returns (uint256) {
        require(MIN_TICK <= tick && tick <= MAX_TICK, "tick out of range");
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast) tick bounded
            return roiLogToPrice(MAX_ROI_LOG - int256(tick));
        }
    }

    function roiLogToPrice(int256 roiLog) internal pure returns (uint256) {
        unchecked {
            int256 x = LN_1_025_WAD * roiLog;
            uint256 price;
            if (roiLog >= 0) {
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

    /// @dev Converts a price to a tick-aligned price and a tick that maps to it.
    /// @dev If there are two equally close prices, the higher one is returned.
    function priceToTickAlignedPriceAndTick(uint256 price) internal pure returns (uint256, uint256) {
        unchecked {
            if (price == WAD) return (WAD, MAX_TICK);
            if (price == 0) return (0, MIN_TICK);

            int256 roiLog = log1025(((WAD - price) << 96) / price);

            if (roiLog < MIN_ROI_LOG) return (WAD, MAX_TICK);
            if (roiLog > MAX_ROI_LOG) return (0, MIN_TICK);

            uint256 alignedPrice = roiLogToPrice(roiLog);

            if (alignedPrice > price && roiLog < MAX_ROI_LOG) {
                uint256 nextAlignedPrice = roiLogToPrice(roiLog + 1);
                if (2 * price < alignedPrice + nextAlignedPrice) {
                    alignedPrice = nextAlignedPrice;
                    roiLog += 1;
                }
            } else if (alignedPrice < price && roiLog > MIN_ROI_LOG) {
                uint256 prevAlignedPrice = roiLogToPrice(roiLog - 1);
                if (2 * price >= alignedPrice + prevAlignedPrice) {
                    alignedPrice = prevAlignedPrice;
                    roiLog -= 1;
                }
            }
            // forge-lint: disable-next-item(unsafe-typecast) roiLog bounded
            return (alignedPrice, uint256(MAX_ROI_LOG - roiLog));
        }
    }

    /// @dev Returns an approximation of the log base 1.025.
    /// @dev x must be a 96-bit fixed-point number.
    function log1025(uint256 x) internal pure returns (int256) {
        uint256 msb;
        assembly {
            msb := sub(255, clz(x))
        }

        uint256 mpow;
        if (msb >= 128) {
            mpow = x >> (msb - 127);
        } else {
            mpow = x << (127 - msb);
        }

        // forge-lint: disable-next-item(unsafe-typecast) msb is a bit position
        int256 log2X6 = (int256(msb) - 96) << 6;

        assembly ("memory-safe") {
            mpow := shr(127, mul(mpow, mpow))
            let highbit := shr(128, mpow)
            log2X6 := or(log2X6, shl(5, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2X6 := or(log2X6, shl(4, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2X6 := or(log2X6, shl(3, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2X6 := or(log2X6, shl(2, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2X6 := or(log2X6, shl(1, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2X6 := or(log2X6, highbit)
        }

        return (log2X6 * INV_LOG2_1_025_X96 + (1 << 101)) >> 102;
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
