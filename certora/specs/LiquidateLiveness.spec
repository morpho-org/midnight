// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired."

This is an existential liveness claim: for every (unhealthy ∨ expired) borrower with debt > 0,
there exists a `liquidate(...)` call that succeeds. One witness per state-space partition is enough,
and the minimal witness is `repaidUnits = 1` (the weakest possible non-trivial liquidation).

Stronger statements ("the entire collateral can be seized in one call" / "the entire debt can be
repaid in one call") live in LiquidateLivenessStronger.spec.
*/

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    /// ENVFREE VIEWS ///
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    /// ORACLE: deterministic, non-reverting price per oracle address.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    /// Skip touchMarket's first-time validation: we want a pre-existing market, and the validation cannot be triggered by liquidate alone in the liveness scenario.
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    /// TOKEN TRANSFERS: well-behaved (no revert, no return-false). The converse is in Reverts.spec.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// MULDIV with tight rounding axioms (proved in MulDiv.spec).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// CONSTANTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition MAX_UINT128() returns mathint = (1 << 128) - 1;

definition MAX_TIMESTAMP() returns mathint = 1 << 64;

definition TIME_TO_MAX_LIF() returns uint256 = 15 * 60;

/// SUMMARIES ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

persistent ghost summaryPrice(address) returns uint256;

// Axioms bounds proven in MulDiv.spec (mulDivDownRoundsDown, mulDivDownTightBound).
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivDown(a, b, d) <= a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivDown(a, d, d) == a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivDown(0, a, d) == 0 && ghostMulDivDown(a, 0, d) == 0;
}

// Axioms bounds proven in MulDiv.spec (mulDivUpRoundsUp, mulDivUpTightBound).
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivUp(a, b, d) <= a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(a, d, d) == a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(0, a, d) == 0 && ghostMulDivUp(a, 0, d) == 0;

    // Monotonicity in first arg — often needed to relate helper to contract:
    axiom forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 && a1 <= a2 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);
}

/// Case-analysis on the common deterministic patterns (y == d, x == d, zero inputs).
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

/// INVARIANT (proven in CollateralBitmap.spec; assumed here via requireInvariant) ///

strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// HELPERS ///

/// Per-collateral validity (lltv, maxLif, ExactMath bounds) and LIVENESS bounds `C_i * P_i <= ORACLE_PRICE_SCALE * WAD * MAX_UINT128`.
function validCollateralAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) {
    uint256 lltv = market.collateralParams[i].lltv;
    uint256 maxLif = market.collateralParams[i].maxLif;

    require lltv > 0 && lltv <= WAD(), "valid lltv";
    require maxLif >= WAD(), "valid maxLif";
    require lltv < WAD() => to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "ExactMath condition for RCF denominator WAD - lif*lltv/WAD is positive";
    require to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * to_mathint(WAD()), "ExactMath condition for RCF denominator WAD - lif*lltv/WAD is positive";

    address oracle = market.collateralParams[i].oracle;
    require to_mathint(collateral(id, borrower, i)) * to_mathint(summaryPrice(oracle)) <= to_mathint(ORACLE_PRICE_SCALE()) * to_mathint(WAD()) * MAX_UINT128(), "...";
}

/// 2-collateral market, bitmap == 3 (bits 0+1 set); matches `loop_iter: 2`. Length-1 regressed `RepayAll` and `RcfMaxNoBadDebt` (see git history).
function dualCollateralSetup(Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 2, "two-collateral market";
    require collateralBitmap(id, borrower) == 3, "bitmap is exactly 3 (bits 0 and 1 set)";

    require summaryGetBit(3, 0) && summaryGetBit(3, 1), "ghost: bits 0 and 1 are set";
    require forall uint256 i. i >= 2 => !summaryGetBit(3, i), "ghost: no other bit is set";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
}

/// Shared preamble: dual-collateral setup, well-behaved env, activated collaterals, feasible loss accounting, unlocked, positive debt.
function commonDualPreamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    dualCollateralSetup(market, id, borrower);

    require e.msg.value == 0, "no value sent";
    require market.liquidatorGate == 0, "no liquidator gate (see Reverts.spec)";
    require e.block.timestamp < MAX_TIMESTAMP(), "timestamp bounded";
    require market.maturity < MAX_TIMESTAMP(), "maturity bounded";

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt, "totalUnits >= borrower debt (Midnight.spec totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";
    require to_mathint(withdrawable(id)) + to_mathint(debtOf(id, borrower)) <= MAX_UINT128(), "withdrawable += repaidUnits won't overflow";

    require !liquidationLocked(id, borrower), "not locked";
    require _debt > 0, "borrower has debt";

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
}

/// On top of `commonDualPreamble`, adds the liveness bound on collateral 0
/// (worst-case `lif = maxLif` absorbs the 1-unit seizure). Used by OneUnit variants.
function oneUnitDualPreamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    commonDualPreamble(e, market, id, borrower);

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    require maxLif * ORACLE_PRICE_SCALE() <= collat * WAD() * summaryPrice(oracle), "LIVENESS: collat 0 absorbs the 1-unit seizure at maxLif";
}

/// Compute `repaidUnits = seizedAssets * P / SCALE * WAD / lif` for Strategy A (seizedAssets = collat) when `lif = maxLif`.
/// Used here only by the RCF escape hatch precondition in the lltv < WAD case.
function strategyARepaidUnitsAtMaxLif(Midnight.Market market, uint128 collat) returns uint256 {
    address oracle = market.collateralParams[0].oracle;
    uint256 maxLif = market.collateralParams[0].maxLif;
    uint256 step1 = summaryMulDivUp(collat, summaryPrice(oracle), ORACLE_PRICE_SCALE());
    return summaryMulDivUp(step1, WAD(), maxLif);
}

/// RULES ///

/// Sanity baseline: liquidate(0, 0, ...) does not revert on any liquidatable position.
/// Only realizes bad debt; useful as a baseline to confirm the well-behaved environment is correctly set up.
rule liquidateZeroZeroNoRevert(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    commonDualPreamble(e, market, id, borrower);
    require e.block.timestamp > market.maturity || !isHealthy(market, id, borrower), "expired or unhealthy";

    /// Route via maturity path if post-maturity, else unhealthy path (NotLiquidatable gates each accordingly).
    bool healthyPath = e.block.timestamp > market.maturity;
    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, healthyPath, receiver, 0, data);
    assert !lastReverted;
}

/// Each rule witnesses "repaidUnits = 1 can be liquidated" in one partition of the (unhealthy ∨ expired) state space.

/// Pre-maturity unhealthy, `lltv[0] == WAD`. RCF `maxRepaid` collapses to `type(uint256).max`.
rule liquidatableCanBeLiquidatedPreMaturityLltvFullDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp <= market.maturity, "pre-maturity";
    require !isHealthy(market, id, borrower), "unhealthy";
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD => RCF denominator vanishes";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// Post-maturity (merged Ramped + Pinned). Union of regimes covers all `timestamp > maturity`:
/// `lif` is either ramped in `[WAD, maxLif)` (healthy + within-window) or pinned at `maxLif`
/// (unhealthy or `timestamp >= maturity + TIME_TO_MAX_LIF`). No RCF check (post-maturity).
rule liquidatableCanBeLiquidatedPostMaturityDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity";

    /// healthyPath=true: post-maturity gating and no RCF check.
    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

/// Pre-maturity unhealthy, `lltv[0] < WAD`, RCF actually engaged. 
/// Uses the rcfThreshold escape hatch : requiring `rcfThreshold > strategyARepaidUnitsAtMaxLif`
/// makes the escape-hatch disjunct hold unconditionally, sidestepping `maxRepaid`.
rule liquidatableCanBeLiquidatedPreMaturityRcfEngagedDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp <= market.maturity, "pre-maturity";
    require !isHealthy(market, id, borrower), "unhealthy (healthyPath=false branch, lif pinned at maxLif Midnight.sol:643)";
    require market.collateralParams[0].lltv < WAD(), "lltv < WAD => RCF maxRepaid is finite, formula actually evaluated";

    uint128 collat = collateral(id, borrower, 0);
    require market.rcfThreshold > strategyARepaidUnitsAtMaxLif(market, collat), "rcfThreshold escape hatch trivializes RCF";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}
