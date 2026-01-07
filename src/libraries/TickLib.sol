// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "./ConstantsLib.sol";

// Min and max useful ticks
int256 constant MIN_TICK = -1679;
int256 constant MAX_TICK = 1679;
// x96 unit
uint256 constant X96 = 1 << 96;
int256 constant X96_INT = 1 << 96;
// ln(1.025)x96
int256 constant LN_1_025_DELTA_X96 = 1956350323211722979786136201;
// ln(2)x96
int256 constant LN2_X96 = 54916777467707473351141471128;
// (1/log2(1.025))x64
int256 constant INV_LOG2_1_025_X96 = 2224016485364590939422807110544;

library TickLib {
    /// @dev Tick range is not checked.
    function tickToPrice(int256 tick) internal pure returns (uint256) {
        uint256 roiWad = WAD * tickToRoi(tick) / X96;
        return WAD * WAD / (WAD + roiWad);
    }

    /// @dev Tick range is not checked.
    function tickToRoi(int256 tick) internal pure returns (uint256) {
        int256 exp = LN_1_025_DELTA_X96 * tick;
        if (tick >= 0) {
            return expX96(uint256(exp));
        } else {
            return (X96 * X96) / expX96(uint256(-exp));
        }
    }

    function roiToTick(uint256 roi) internal pure returns (int256) {
        if (roi == 0) return MIN_TICK;

        uint256 msb;
        assembly ("memory-safe") {
            msb := shl(7, lt(0xffffffffffffffffffffffffffffffff, roi))
            msb := or(msb, shl(6, lt(0xffffffffffffffff, shr(msb, roi))))
            msb := or(msb, shl(5, lt(0xffffffff, shr(msb, roi))))
            msb := or(msb, shl(4, lt(0xffff, shr(msb, roi))))
            msb := or(msb, shl(3, lt(0xff, shr(msb, roi))))
            msb := or(msb, shl(2, lt(0xf, shr(msb, roi))))
            msb := or(msb, shl(1, lt(0x3, shr(msb, roi))))
            msb := or(msb, lt(0x1, shr(msb, roi)))
        }

        uint256 mpow;
        if (msb >= 128) {
            mpow = roi >> (msb - 127);
        } else {
            mpow = roi << (127 - msb);
        }

        int256 log2roiX96 = (int256(msb) - 96) << 96;

        assembly ("memory-safe") {
            mpow := shr(127, mul(mpow, mpow))
            let highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(95, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(94, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(93, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(92, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(91, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(90, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(89, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(88, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(87, highbit))
            mpow := shr(highbit, mpow)

            mpow := shr(127, mul(mpow, mpow))
            highbit := shr(128, mpow)
            log2roiX96 := or(log2roiX96, shl(86, highbit))
        }

        return (log2roiX96 * INV_LOG2_1_025_X96 + (1 << 191)) >> 192;
    }

    function expX96(uint256 x) private pure returns (uint256) {
        unchecked {
            int256 q = (int256(x) + LN2_X96 / 2) / LN2_X96;
            int256 r = int256(x) - q * LN2_X96;
            int256 secondTerm = (r * r) >> 97;
            int256 thirdTerm = (secondTerm * r / 3) >> 96;
            int256 expR = X96_INT + r + secondTerm + thirdTerm;
            return uint256(expR) << uint256(q);
        }
    }
}
