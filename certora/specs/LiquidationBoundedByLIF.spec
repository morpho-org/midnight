// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic toId summary using a wrapper that extracts all scalar Market fields.
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market);

    // Skip market creation logic: removes the collateral-validation loop.
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

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

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

// Axioms proven in MulDiv.spec (mulDivDownRoundsDown, mulDivDownTightBound).
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
}

// Axioms proven in MulDiv.spec (mulDivUpRoundsUp, mulDivUpTightBound).
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivDown(x, y, d);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivUp(x, y, d);
}

/// INVARIANTS ///

/// Proven in CollateralBitmap.spec; assumed here via requireInvariant (not re-proven in this spec).
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// LIF BOUNDARIES ///

/// Liquidation profit is bounded by maxLif (repaidUnits input).
/// Unlike the seizedAssets rule, no requireInvariant is needed here: if collateralIndex is not in the bitmap because mulDivDown(..., 0) reverts.
rule liquidationProfitBoundedInputRepaidUnits(env e, Midnight.Market market, uint256 collateralIndex, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool healthyPath) {
    mathint maxLif = market.collateralParams[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness (see touchMarket validation and ExactMath.spec)";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, market, collateralIndex, 0, repaidUnits, borrower, healthyPath, receiver, callback, data);

    mathint price = summaryPrice(market.collateralParams[collateralIndex].oracle);

    assert seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBoundedSeizedAssets(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, address borrower, address receiver, address callback, bytes data, bool healthyPath) {
    mathint maxLif = market.collateralParams[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness (see touchMarket validation and ExactMath.spec)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec,
    bytes32 id0 = summaryToId(market);
    requireInvariant nonZeroCollateralsAreActivated(id0, borrower, collateralIndex);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, market, collateralIndex, seizedAssets, 0, borrower, healthyPath, receiver, callback, data);

    mathint price = summaryPrice(market.collateralParams[collateralIndex].oracle);

    assert seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}
