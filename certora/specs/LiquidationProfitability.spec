// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isHealthy(Midnight.Obligation obligation, bytes32 id, address borrower) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Summarize mulDivDown and mulDivUp by ghost functions for prover performance.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Deterministic toId summary using a wrapper that extracts all scalar Obligation fields.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation);

    // Skip obligation creation logic: removes the collateral-validation loop.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryToId(obligation);

    // Token transfers happen after return values are computed; irrelevant to the assertion.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition TIME_TO_MAX_LIF() returns uint256 = 900; // 15 min

persistent ghost summaryPrice(address) returns uint256;

// Axioms proven in MulDiv.spec (mulDivDownTightBound, mulDivDownRoundsDown).
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
}

// Axioms proven in MulDiv.spec (mulDivUpUpperBound, mulDivUpRoundsUp).
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d < a * b + d;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
}

function summaryToId(Midnight.Obligation obligation) returns bytes32 {
    return Utils.hashObligation(obligation);
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

/// LIF CHARACTERIZATION ///

/// For repaidUnits input: lif >= WAD (solvency), and lif == maxLif when borrower is unhealthy or >= 15 min post-maturity (profitability).
rule liquidationLifRepaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    uint256 maxLif = obligation.collateralParams[collateralIndex].maxLif;
    require maxLif >= WAD(), "see the rule maxLifIsAtLeastWad";

    bytes32 id = toId(e, obligation);
    bool maxLifReached = !isHealthy(obligation, id, borrower) || e.block.timestamp >= require_uint256(obligation.maturity + TIME_TO_MAX_LIF());

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, receiver, callback, data);

    mathint price = summaryPrice(obligation.collateralParams[collateralIndex].oracle);

    // lif >= WAD: liquidator receives collateral worth at least the repaid debt (up to 1 unit floor rounding on seizedAssets) at the oracle price.
    assert (seizedResult + 1) * price >= repaidResult * ORACLE_PRICE_SCALE();

    // lif == maxLif when borrower is unhealthy or >= 15 min post-maturity: full liquidation incentive factor applies.
    assert maxLifReached => (seizedResult + 1) * price * WAD() + ORACLE_PRICE_SCALE() * WAD() > repaidResult * maxLif * ORACLE_PRICE_SCALE();
}

/// For seizedAssets input: lif >= WAD (solvency), and lif == maxLif when borrower is unhealthy or >= 15 min post-maturity (profitability).
rule liquidationLifSeizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, address receiver, address callback, bytes data) {
    uint256 maxLif = obligation.collateralParams[collateralIndex].maxLif;
    require maxLif >= WAD(), "see the rule maxLifIsAtLeastWad";

    bytes32 id = toId(e, obligation);
    bool maxLifReached = !isHealthy(obligation, id, borrower) || e.block.timestamp >= require_uint256(obligation.maturity + TIME_TO_MAX_LIF());

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, receiver, callback, data);

    mathint price = summaryPrice(obligation.collateralParams[collateralIndex].oracle);

    // lif >= WAD: liquidator receives collateral worth at least the repaid debt (up to 1 unit ceil rounding on repaidUnits) at the oracle price.
    assert seizedResult * price > (repaidResult - 1) * ORACLE_PRICE_SCALE();

    // lif == maxLif when borrower is unhealthy or >= 15 min post-maturity: full liquidation incentive factor applies.
    assert maxLifReached => seizedResult * price * WAD() + ORACLE_PRICE_SCALE() * WAD() > (repaidResult - 1) * maxLif * ORACLE_PRICE_SCALE();
}
