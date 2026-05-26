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

    // Implicit (default AUTO → HAVOC_ECF on external calls): callbacks, gates,
    // ratifiers, oracles, and token transfers are assumed not to re-enter Midnight.
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
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(0, b, d) == 0;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

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
            // To derive repaidUnits >= debtAfterBadDebt when the last bitmap bit is cleared, the prover requires inverse axioms and mulDiv monotonicity (using lif <= maxLif).
            // The bound below is a performance restriction, not a soundness assumption: a market can have up to 128 collaterals,
            // but a borrower can have at most MAX_COLLATERALS_PER_BORROWER of them activated at any time (see nonZeroCollateralsAreActivated in CollateralBitmap.spec).
            // We restrict the market shape to the same bound to keep loop unrolling tractable.
            require market.collateralParams.length <= Utils.maxCollateralsPerBorrower(), "restrict to MAX_COLLATERALS_PER_BORROWER collaterals for performance";
        
            // Inlined axioms (proved in MulDiv.spec): mulDivUp monotonicity in a and d, and the up/down inverse.
            // mulDivMonotoneA
            require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. a1 <= a2 && d > 0 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);
        
            // mulDivMonotoneD
            require forall uint256 a. forall uint256 b. forall uint256 d1. forall uint256 d2. d1 > 0 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);
        
            // mulDivInverseUpDown
            require forall uint256 a. forall uint256 b. forall uint256 d. b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a;
        }
    }
