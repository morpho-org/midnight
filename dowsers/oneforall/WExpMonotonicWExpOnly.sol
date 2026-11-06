// SPDX-License-Identifier: GPL-2.0-or-later
//
//   dowsersRun OneForAll dowsers/oneforall/WExpMonotonicWExpOnly.sol WExpMonotonic
//
// Isolation variant of WExpMonotonic.sol: TickLib trimmed to wExp alone, kept
// verbatim including the self-call wExp(-x). If the translator also hangs on
// this file, the recursion is the blocker; if it translates, the problem is in
// tickToPrice/priceToTick (the using-for call or the while loop).
//
pragma solidity 0.8.34;

library TickLib {
    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            if (x < 0) {
                return 1e36 / wExp(-x);
            } else {
                int256 ln2 = 0.693147180559945309e18; // floor(ln(2) * 1e18)
                // offset is chosen such that 2 * expR(-offset) == expR(ln2 - offset - 1), so wExp is non-decreasing.
                int256 offset = 0.32261121498945987e18;
                int256 q = (x + offset) / ln2;
                int256 r = x - q * ln2;
                int256 secondTerm = r * r / (2 * 1e18);
                int256 thirdTerm = secondTerm * r / (3 * 1e18);
                int256 expR = 1e18 + r + secondTerm + thirdTerm;
                // - q is non-negative because x is non-negative in this branch
                // - expR is positive because |r| < ln2 < 1e18 and |secondTerm| > |thirdTerm|
                return uint256(expR) << uint256(q);
            }
        }
    }
}

contract WExpMonotonic {
    // LN_ONE_PLUS_DELTA * (MAX_TICK / 2), the largest |x| tickToPrice produces.
    int256 internal constant MAX_INPUT = 16817989975223754156;

    function verify(int256 x) public pure {
        require(x >= -MAX_INPUT && x < MAX_INPUT);
        assert(TickLib.wExp(x) <= TickLib.wExp(x + 1));
    }
}
