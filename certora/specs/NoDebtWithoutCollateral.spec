// SPDX-License-Identifier: GPL-2.0-or-later

/* Proves: a position can never carry debt while having no active collateral bit, i.e.:
 *   position[id][user].collateralBitmap == 0  =>  position[id][user].debt == 0
 *
 * Combined with `nonZeroCollateralsAreActivated` (proved in CollateralBitmap.spec),
 * this implies the full semantic property: no position can have collateral[i] == 0 for every i while having debt > 0.
 */

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;

    // Internal library summaries.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Implicit (default AUTO → HAVOC_ECF on external calls): callbacks, gates,
    // ratifiers, oracles, and token transfers are assumed not to re-enter Midnight.
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivDownM(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivUpM(a, b, d));
}

// Mirrors ConstantsLib.sol; same pattern as CollateralBitmap.spec.
definition MAX_COLLATERALS_PER_BORROWER() returns uint256 = 10;

/// MULDIV GHOSTS ///

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDownM(0, b, d) == 0;
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint;

/* Axioms proved in MulDiv.spec. */

/* proved in mulDivMonotoneA */
definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);

/* proved in mulDivMonotoneD */
definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => summaryMulDivUpM(a, b, d1) >= summaryMulDivUpM(a, b, d2);

/* proved in mulDivInverseUpDown */
definition axiomInverseUpDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b > 0 && d > 0 => summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b) <= a;

// Minimal mulDiv axioms needed for liquidate's bad-debt + repayment cancellation argument.
function requireLiquidateMulDivAxioms() {
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d);
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2);
    require forall mathint a. forall mathint b. forall mathint d. axiomInverseUpDown(a, b, d);
}

/// INVARIANT ///

weak invariant noDebtWithoutCollateral(bytes32 id, address user)
    currentContract.position[id][user].collateralBitmap == 0 => currentContract.position[id][user].debt == 0
    {
        preserved take(Midnight.Offer offer, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, bytes ratifierData) with (env e) {
            // Transient storage is logically zero at the start of an externally-initiated tx.
            require !liquidationLocked(id, taker), "transient lock zero at tx start";
            require !liquidationLocked(id, offer.maker), "transient lock zero at tx start";
        }
        preserved liquidate(Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool healthyPath, address receiver, address callback, bytes data) with (env e) {
            // Liquidate's debt-zeroing math (badDebt absorbed + repayment) needs mulDiv monotonicity + inverse axioms 
            // (proved in MulDiv.spec) so the prover can derive repaidUnits >= debt_after_badDebt when the last bitmap bit is cleared.
            require market.collateralParams.length <= MAX_COLLATERALS_PER_BORROWER(), "restrict to MAX_COLLATERALS_PER_BORROWER collaterals";
            requireLiquidateMulDivAxioms();
        }
    }
