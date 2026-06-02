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

    // Mirror the transient liquidation-lock slot into the persistent ghost `ghostLocked`.
    // The lock must be a persistent ghost rather than the raw transient slot for two reasons:
    //  1. Invariants reset transient storage at the transaction boundary (only the base step
    //     assumes it nullified, see https://docs.certora.com/en/latest/docs/cvl/transient.html),
    //     which would clear the lock while the persistent debt/bitmap state remains.
    //  2. Havoc (multicall's HAVOC_ALL, and unresolved external calls) havocs transient storage
    //     just like regular storage; a persistent ghost survives havoc. This is sound because a
    //     non-reentrant callee cannot write currentContract's transient storage.
    function UtilsLib.tExchange(uint256 baseSlot, bytes32 key1, address key2, bool value) internal returns (bool) => summaryTExchange(key1, key2, value);
    function UtilsLib.tGet(uint256 baseSlot, bytes32 key1, address key2) internal returns (bool) => summaryTGet(key1, key2);
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
            require market.collateralParams.length <= 10, "assume less than 10 collaterals so that the loop can be bounded";
        
            // Inlined axioms (proved in MulDiv.spec): mulDivUp monotonicity in a and d, and the up/down inverse.
            // mulDivMonotoneA
            require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. a1 <= a2 && d > 0 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d), "see mulDivMonotoneA";
        
            // mulDivMonotoneD
            require forall uint256 a. forall uint256 b. forall uint256 d1. forall uint256 d2. d1 > 0 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2), "see mulDivMonotoneD";
        
            // mulDivInverseUpDown
            require forall uint256 a. forall uint256 b. forall uint256 d. b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a, "see mulDivInverseUpDown";
        }
    }

weak invariant liquidationLockClearedAtBoundary(bytes32 id, address user)
    ghostLocked[id][user] == false;

weak invariant noDebtWithoutCollateral(bytes32 id, address user)
    currentContract.position[id][user].collateralBitmap == 0 => currentContract.position[id][user].debt == 0
    {
        preserved {
            requireInvariant lockedOrNoDebtWithoutCollateral(id, user);
            requireInvariant liquidationLockClearedAtBoundary(id, user);
        }
    }
