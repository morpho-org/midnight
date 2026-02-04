// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

int256 constant LN_ONE_PLUS_DELTA = 0.024692612590371501e18; // ln(1 + 0.025)
uint256 constant TICK_RANGE = 990;

library TickLib {
    using TickLib for uint256;

    /// @dev Returns (`x` + `d` - 1) / `d` rounded up, without checking for overflow.
    function divHalfDownUnchecked(uint256 x, uint256 d) internal pure returns (uint256) {
        unchecked {
            return (x + (d - 1) / 2) / d;
        }
    }

    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            if (x < 0) {
                return 1e36 / wExp(-x);
            } else {
                int256 ln2 = 0.693147180559945309e18;
                int256 q = (x + ln2 / 2) / ln2;
                int256 r = x - q * ln2;
                int256 secondTerm = r * r / (2 * 1e18);
                int256 thirdTerm = secondTerm * r / (3 * 1e18);
                int256 expR = 1e18 + r + secondTerm + thirdTerm;
                // forge-lint: disable-next-item(unsafe-typecast)
                // - q is non-negative because x is non-negative in this branch
                // - expR is positive because |r| < ln2 < 1e18 and |secondTerm| > |thirdTerm|
                return uint256(expR) << uint256(q);
            }
        }
    }

    function tickToPrice(uint256 tick) internal pure returns (uint256) {
        require(tick <= TICK_RANGE, "tick out of range");
        unchecked {
            // forge-lint: disable-next-item(unsafe-typecast)
            return uint256(1e36)
                    .divHalfDownUnchecked(1e18 + wExp(LN_ONE_PLUS_DELTA * (int256(TICK_RANGE / 2) - int256(tick))))
                    .divHalfDownUnchecked(1e13) * 1e13;
        }
    }

    /// @dev Returns the lowest tick with a higher price.
    function priceToTick(uint256 price) internal pure returns (uint256) {
        require(price <= 1e18, "Price is greater than one");
        uint256 low = 0;
        uint256 high = TICK_RANGE;
        while (low != high) {
            unchecked {
                uint256 mid = (low + high) / 2;
                if (tickToPrice(mid) < price) low = mid + 1;
                else high = mid;
            }
        }
        return low;
    }
}
