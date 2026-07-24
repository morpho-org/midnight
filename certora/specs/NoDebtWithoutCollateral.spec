// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

/* Proves: a position can never carry debt while having no active collateral bit, i.e.:
 *   position[id][user].collateralBitmap == 0  =>  position[id][user].debt == 0
 *
 * Combined with `nonZeroCollateralsAreActivated` (proved in CollateralBitmap.spec),
 * this implies the full semantic property: no position can have collateral[i] == 0 for every i while having debt > 0.
 *
 * The spec is verified under two confs because the two halves need opposite call modelings:
 *
 *  - NoDebtWithoutCollateralNative.conf (-havocAllByDefault true): proves the strong invariant `lockedOrNoDebtWithoutCollateral`. 
 *    HAVOC_ALL at every external call is the sound modeling of reentrancy on the *regular* storage (debt/bitmap).
 *
 *  - NoDebtWithoutCollateralNativeLock.conf  (no -havocAllByDefault): proves the lock facts
 *    `liquidationLockClearedAtBoundary` and `liquidationLockNeutral`. The default AUTO summary
 *    (HAVOC_ECF for state-changers, NONDET for views) leaves currentContract storage untouched, which is
 *    faithful for the transient lock: an external callee cannot tstore Midnight's transient namespace, and
 *    reentrant Midnight code restores the lock (proved by `liquidationLockNeutral`). This is the induction
 *    "assume external calls leave the lock unchanged, prove every method does, conclude by induction".
 */

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.maxCollateralsPerBorrower() external returns (uint256) envfree;

    // Summarize the oracle price read in the liquidate() collateral loop.
    // price() is a view (staticcall): it cannot mutate state or reenter with side effects, so
    // the storage HAVOC_ALL that -havocAllByDefault applies to the unresolved call models
    // behavior the EVM forbids -- dropping it is sound, and that per-iteration havoc is the
    // dominant SMT cost. NONDET still returns a fully adversarial value (which may differ
    // across reads of the same oracle), so it cannot hide a price-dependent bug.
    function _.price() external => NONDET;

    // Internal library summaries.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// MULDIV SUMMARIES ///

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
    liquidationLocked(id, user) || (currentContract.position[id][user].collateralBitmap == 0 => currentContract.position[id][user].debt == 0)
    {
        preserved liquidate(Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) with (env e) {
            // To derive repaidUnits >= debtAfterBadDebt when the last bitmap bit is cleared, the prover requires inverse axioms and mulDiv monotonicity (using lif <= maxLif).
            require market.collateralParams.length <= 10, "assume less than 10 collaterals so that the loop can be bounded";
        
            require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. a1 <= a2 && d > 0 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d), "see mulDivMonotoneA";
        
            require forall uint256 a. forall uint256 b. forall uint256 d1. forall uint256 d2. d1 > 0 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2), "see mulDivMonotoneD";
        
            require forall uint256 a. forall uint256 b. forall uint256 d. b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a, "see mulDivInverseUpDown";
        }
        preserved onTransactionBoundary with (env e) {
            requireInvariant liquidationLockClearedAtBoundary(id, user);
        }
    }

weak invariant liquidationLockClearedAtBoundary(bytes32 id, address user)
    !liquidationLocked(id, user);

// Lemma justifying that external calls leave the liquidation lock unchanged, where callbacks are HAVOC_ECF and so cannot touch currentContract's transient storage). 
// This is the induction step that makes the HAVOC_ECF modeling of the lock (liquidationLockClearedAtBoundary) faithful, including under reentrancy.
rule liquidationLockNeutral(method f, env e, calldataarg args, bytes32 id, address user) {
    bool before = liquidationLocked(id, user);
    f(e, args);
    assert liquidationLocked(id, user) == before;
}
