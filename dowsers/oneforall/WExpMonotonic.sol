// SPDX-License-Identifier: BUSL-1.1
//
// OneForAll port of the wExp monotonicity argument in certora/specs/TickToPrice.spec.
//
//   dowsersRun OneForAll dowsers/oneforall/WExpMonotonic.sol WExpMonotonicProperties
//
// The CVL rules wExpIsMonotonicOnNegativeRange,
// wExpIsMonotonicOnPositiveRangeWhenQStays and
// wExpIsMonotonicOnPositiveRangeWhenQJumps are one assertion here:
// verify_wExpIsMonotonic. Those rules prove the step for consecutive inputs.
// The ghost axiom `x <= y => wExp(x) <= wExp(y)` is that step plus induction,
// which this file does not do.
//
// Divergences from src/libraries/TickLib.sol, all deliberate:
//
// * One file. OneForAll uploads only the .sol named on the command line.
// * Checked arithmetic. TickLib.wExp is unchecked, so a negative expR or a
//   negative q wraps in the casts. wExpCasting proves expR >= 0 and q >= 0
//   on this range, and q is far below 256. OneForAll's cast of a negative
//   int256 to uint256 wraps, so those requires drop traces outside the
//   proved range.
// * The CVL split on q is not repeated. When q jumps, the cubic expR(r) is
//   compared with 2 * expR(r + 1 - ln2), and the offset is chosen so those
//   sides meet. That comparison stays inside the one assert. Certora splits
//   it out because the symbolic bound does not go through otherwise.
// * The assert is the comparison itself. A product in Spec.Ensures hangs the
//   translator.
//
pragma solidity 0.8.34;

int256 constant LN_ONE_PLUS_DELTA = 0.004987541511039073e18; // floor(ln(1.005) * 1e18)
int256 constant LN2 = 0.693147180559945309e18; // floor(ln(2) * 1e18)
// Chosen so that 2 * expR(-offset) == expR(ln2 - offset - 1).
int256 constant OFFSET = 0.32261121498945987e18;
uint256 constant MAX_TICK = 6744;

/// @dev Largest |input| of wExp inside tickToPrice: ln(1.005) * (MAX_TICK / 2), in WAD.
int256 constant MAX_INPUT = LN_ONE_PLUS_DELTA * int256(MAX_TICK / 2);

contract WExpMonotonicProperties {
    /// @dev TickLib.wExp. The negative branch recurses on -x.
    function wExp(int256 x) public pure returns (uint256) {
        if (x < 0) return uint256(1e36) / wExp(-x);

        int256 q = (x + OFFSET) / LN2;
        int256 r = x - q * LN2;
        int256 secondTerm = r * r / (2 * 1e18);
        int256 thirdTerm = secondTerm * r / (3 * 1e18);
        int256 expR = 1e18 + r + secondTerm + thirdTerm;
        require(q >= 0 && q < 256, "q fits a uint256 shift");
        require(expR >= 0, "expR is non-negative");
        return uint256(expR) << uint256(q);
    }

    /// @dev Consecutive step: wExp(x) <= wExp(x + 1) on the tickToPrice range.
    function verify_wExpIsMonotonic(int256 x) external pure returns (uint256 atX, uint256 atNext) {
        require(-MAX_INPUT <= x && x < MAX_INPUT, "wExp is only called on inputs in this range");
        atX = wExp(x);
        atNext = wExp(x + 1);
        assert(atX <= atNext);
    }
}
