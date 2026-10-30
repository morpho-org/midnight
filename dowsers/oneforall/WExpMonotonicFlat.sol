// SPDX-License-Identifier: GPL-2.0-or-later
//
//   dowsersRun OneForAll dowsers/oneforall/WExpMonotonicFlat.sol WExpMonotonic
//
// Same check as WExpMonotonicWExpOnly.sol, with the one recursion level of wExp
// unrolled: for x < 0 the original computes 1e36 / wExp(-x), and -x > 0 always
// takes the else branch, so computing the positive branch on |x| directly is
// identical. If this file translates while WExpMonotonicWExpOnly stalls, the
// translator cannot handle the self-call wExp(-x).
//
pragma solidity 0.8.34;

library TickLib {
    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            // Original: if (x < 0) return 1e36 / wExp(-x); else <positive branch on x>.
            // The recursive call is always on a non-negative argument, so it is
            // the positive branch on -x. Compute it on y = |x| instead.
            int256 y = x < 0 ? -x : x;
            int256 ln2 = 0.693147180559945309e18; // floor(ln(2) * 1e18)
            // offset is chosen such that 2 * expR(-offset) == expR(ln2 - offset - 1), so wExp is non-decreasing.
            int256 offset = 0.32261121498945987e18;
            int256 q = (y + offset) / ln2;
            int256 r = y - q * ln2;
            int256 secondTerm = r * r / (2 * 1e18);
            int256 thirdTerm = secondTerm * r / (3 * 1e18);
            int256 expR = 1e18 + r + secondTerm + thirdTerm;
            // - q is non-negative because x is non-negative in this branch
            // - expR is positive because |r| < ln2 < 1e18 and |secondTerm| > |thirdTerm|
            uint256 positive = uint256(expR) << uint256(q);
            return x < 0 ? 1e36 / positive : positive;
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
