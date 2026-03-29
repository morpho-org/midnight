// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic toId summary using a ghost that takes simple types (no struct).
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryObligationId(obligation.loanToken, obligation.maturity);

    // Skip obligation creation logic: removes the collateral-validation loop.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryObligationId(obligation.loanToken, obligation.maturity);

    // Token transfers happen after return values are computed; irrelevant to the assertion.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryObligationId(address, uint256) returns bytes32;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivDown(x, y, d);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivUp(x, y, d);
}

/// INVARIANTS ///

/// Proven in CollateralBitmap.spec; assumed here via requireInvariant (not re-proven in this spec).
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 idx)
    idx < 128 => (collateralOf(id, user, idx) != 0 <=> summaryGetBit(currentContract.position[id][user].activatedCollaterals, idx));

/// LIF BOUNDARIES ///

/// Liquidation profit is bounded by maxLif (repaidUnits input).
/// Unlike the seizedAssets rule, no requireInvariant is needed here: if collateralIndex is not in the bitmap,
/// liquidatedCollatPrice is 0, and mulDivDown(..., 0) reverts (division by zero), making the rule true.
rule liquidationProfitBoundedInputRepaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness (see touchObligation validation and ExactMath.spec)";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBoundedSeizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness (see touchObligation validation and ExactMath.spec)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec,
    // which validates the bitmap abstraction from BitmapSummaries.spec against Bitmap.spec.
    // liquidate reverts when collateralIndex >= 128, so the invariant is a no-op in that case.
    bytes32 id0 = summaryObligationId(obligation.loanToken, obligation.maturity);
    requireInvariant nonZeroCollateralsAreActivated(id0, borrower, collateralIndex);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}
