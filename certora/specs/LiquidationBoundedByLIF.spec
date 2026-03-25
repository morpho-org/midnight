// SPDX-License-Identifier: GPL-2.0-or-later

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

    // Bitmap operation summaries (proven in Bitmap.spec, modeled in BitmapSummaries.spec).
    function UtilsLib.setBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summarySetBit(bitmap, bit);
    function UtilsLib.clearBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summaryClearBit(bitmap, bit);
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => summaryMsb(bitmap);
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryObligationId(address, uint256) returns bytes32;

// Bitmap abstraction (see BitmapSummaries.spec for the proven invariant).
persistent ghost summaryGetBit(uint128, uint256) returns bool {
    axiom forall uint256 bit. !summaryGetBit(0, bit);
}

function summarySetBit(uint128 bitmap, uint256 bit) returns (uint128) {
    uint128 result;
    assert bit < 128;
    require summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherBit. otherBit != bit && otherBit < 128 => summaryGetBit(result, otherBit) == summaryGetBit(bitmap, otherBit), "see Bitmap.spec";
    return result;
}

function summaryClearBit(uint128 bitmap, uint256 bit) returns (uint128) {
    uint128 result;
    assert bit < 128;
    require !summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherBit. otherBit != bit && otherBit < 128 => summaryGetBit(result, otherBit) == summaryGetBit(bitmap, otherBit), "see Bitmap.spec";
    return result;
}

function summaryMsb(uint128 bitmap) returns (uint256) {
    uint256 bit;
    assert bitmap != 0;

    require bit < 128, "see Bitmap.spec";
    require summaryGetBit(bitmap, bit), "see Bitmap.spec";
    require forall uint256 otherBit. summaryGetBit(bitmap, otherBit) => otherBit <= bit, "see Bitmap.spec";
    return bit;
}

/// INVARIANTS ///

/// Proven in BitmapSummaries.spec; assumed here via requireInvariant (not re-proven in this spec).
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

    require collateralIndex < 128, "collateralIndex must be less than 128";
    bytes32 id0 = summaryObligationId(obligation.loanToken, obligation.maturity);
    requireInvariant nonZeroCollateralsAreActivated(id0, borrower, collateralIndex);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}
