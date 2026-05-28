// SPDX-License-Identifier: GPL-2.0-or-later

/* Proves: a position can never carry debt while having no active collateral bit, i.e.:
 *   position[id][user].collateralBitmap == 0  =>  position[id][user].debt == 0
 *
 * Combined with `nonZeroCollateralsAreActivated` (proved in CollateralBitmap.spec),
 * this implies the full semantic property: no position can have collateral[i] == 0 for every i while having debt > 0.
 */

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.maxCollateralsPerBorrower() external returns (uint256) envfree;

    // Internal library summaries.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Mirror the transient liquidation-lock slot into `ghostLocked`.
    // This makes the persistent ghost the source of truth and sidesteps CVL's caveat that transient storage
    // is only nullified in the base step of invariants (see https://docs.certora.com/en/latest/docs/cvl/transient.html).
    function UtilsLib.tExchange(uint256 baseSlot, bytes32 key1, address key2, bool value) internal returns (bool) => summaryTExchange(key1, key2, value);
    function UtilsLib.tGet(uint256 baseSlot, bytes32 key1, address key2) internal returns (bool) => summaryTGet(key1, key2);

    // Pure-view external callbacks: summarized as NONDET on the return value, no storage effect.
    // NONDET is sound here because all five interfaces declare these methods `external view`
    // We make the summaries explicit so they are not affected by `-havocAllByDefault true`, which would model these reads as HAVOC_ALL.
    function _.isRatified(Midnight.Offer, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
    function _.price() external => NONDET;

    // NOTE: stateful external calls (`on*` callbacks and ERC20 `transfer`/`transferFrom`) are
    // intentionally left unresolved. Combined with `-havocAllByDefault true`, this forces the
    // strong-invariant boundary check on `lockedOrNoDebtWithoutCollateral` to fire at every such
    // call site.
}

/// LIQUIDATION-LOCK GHOST ///

persistent ghost mapping(bytes32 => mapping(address => bool)) ghostLocked {
    init_state axiom (forall bytes32 id. forall address user. ghostLocked[id][user] == false);
}

function summaryTExchange(bytes32 id, address user, bool newValue) returns bool {
    bool previous = ghostLocked[id][user];
    ghostLocked[id][user] = newValue;
    return previous;
}

function summaryTGet(bytes32 id, address user) returns bool {
    return ghostLocked[id][user];
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

/// MULDIV GHOSTS ///

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    // proved in mulDivZero in MulDiv.spec.
    axiom forall uint256 b. forall uint256 d. ghostMulDivDown(0, b, d) == 0;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

/// INVARIANT ///

strong invariant lockedOrNoDebtWithoutCollateral(bytes32 id, address user)
    ghostLocked[id][user] || (currentContract.position[id][user].collateralBitmap == 0 => currentContract.position[id][user].debt == 0)
    {
        preserved liquidate(Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool healthyPath, address receiver, address callback, bytes data) with (env e) {
            // To derive repaidUnits >= debtAfterBadDebt when the last bitmap bit is cleared, the prover requires inverse axioms and mulDiv monotonicity (using lif <= maxLif).
            // Scope restriction (not CVL-enforced): contract allows up to MAX_COLLATERALS (128) collateralParams, but a borrower has at most
            // MAX_COLLATERALS_PER_BORROWER (10) activated (see `nonZeroCollateralsAreActivated`); we narrow the market shape to match, for loop-unrolling tractability.
            require market.collateralParams.length <= Utils.maxCollateralsPerBorrower(), "scope restriction: market shape narrowed to <= MAX_COLLATERALS_PER_BORROWER";
        
            // Inlined axioms (proved in MulDiv.spec): mulDivUp monotonicity in a and d, and the up/down inverse.
            // mulDivMonotoneA
            require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. a1 <= a2 && d > 0 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);
        
            // mulDivMonotoneD
            require forall uint256 a. forall uint256 b. forall uint256 d1. forall uint256 d2. d1 > 0 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);
        
            // mulDivInverseUpDown
            require forall uint256 a. forall uint256 b. forall uint256 d. b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a;
        }
    }

weak invariant liquidationLockClearedAtBoundary(bytes32 id, address user)
    ghostLocked[id][user] == false;

// Derived from `lockedOrNoDebtWithoutCollateral` and `liquidationLockClearedAtBoundary`:
//   (ghostLocked[id][user] || (bitmap == 0 => debt == 0)) ∧ !ghostLocked[id][user] ⇒ (bitmap == 0 => debt == 0)
// at every method boundary. The preserved block injects both invariants at the start of the
// inductive step; the heavy mulDiv axioms and loop bound live on `lockedOrNoDebtWithoutCollateral`.
weak invariant noDebtWithoutCollateral(bytes32 id, address user)
    currentContract.position[id][user].collateralBitmap == 0 => currentContract.position[id][user].debt == 0
    {
        preserved {
            requireInvariant lockedOrNoDebtWithoutCollateral(id, user);
            requireInvariant liquidationLockClearedAtBoundary(id, user);
        }
    }
