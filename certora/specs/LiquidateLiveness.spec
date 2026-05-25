// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

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

/// Two-activated-collateral market with bitmap == 3 (bits 0 and 1 set); matches `loop_iter: 2`.
/// Proofs in this spec only formally cover 2-collateral markets. A length-1 generalization
/// was tested and regressed `RepayAll` and both `RcfMaxNoBadDebt` rules; see commit history.
function dualCollateralSetup(Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 2, "two-collateral market";
    require collateralBitmap(id, borrower) == 3, "bitmap is exactly 3 (bits 0 and 1 set)";

    require summaryGetBit(3, 0) && summaryGetBit(3, 1), "ghost: bits 0 and 1 are set";
    require forall uint256 i. i >= 2 => !summaryGetBit(3, i), "ghost: no other bit is set";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
}

/// Replicates the contract's `repaidUnits = seizedAssets * P / SCALE * WAD / lif`
/// for Strategy A (seizedAssets = collat) when `lif = maxLif`
function strategyARepaidUnitsAtMaxLif(Midnight.Market market, uint128 collat) returns uint256 {
    address oracle = market.collateralParams[0].oracle;
    uint256 maxLif = market.collateralParams[0].maxLif;
    uint256 step1 = summaryMulDivUp(collat, summaryPrice(oracle), ORACLE_PRICE_SCALE());
    return summaryMulDivUp(step1, WAD(), maxLif);
}

/// Common preamble used by every dual-setup rule below: 2-collateral market with
/// bitmap == 3, well-behaved env, both collaterals activated, feasible loss
/// accounting, not locked, and positive debt.
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

/// On top of `commonDualPreamble`, adds the LIVENESS bound on collateral 0
/// (worst-case `lif = maxLif` absorbs the 1-unit seizure). Used by OneUnit variants.
function oneUnitDualPreamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    commonDualPreamble(e, market, id, borrower);

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    require maxLif * ORACLE_PRICE_SCALE() <= collat * WAD() * summaryPrice(oracle), "LIVENESS: collat 0 absorbs the 1-unit seizure at maxLif";
}

/// On top of `commonDualPreamble`, restricts to Strategy A (seizing all of
/// collateral 0 at maxLif doesn't fully repay). Returns `collat[0]` so the rule
/// can pass it as `seizedAssets` to `liquidate`. Used by SeizeAll variants.
function seizeAllDualPreamble(env e, Midnight.Market market, bytes32 id, address borrower) returns uint128 {
    commonDualPreamble(e, market, id, borrower);

    uint128 collat = collateral(id, borrower, 0);
    require strategyARepaidUnitsAtMaxLif(market, collat) <= debtOf(id, borrower), "Strategy A applicable";
    return collat;
}

/// RULES ///

/// Sanity baseline: liquidate(0, 0, ...) does not revert on any liquidatable position.
/// Only realizes bad debt; useful as a baseline to confirm the well-behaved environment is correctly set up.
rule liquidateZeroZeroNoRevert(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    dualCollateralSetup(market, id, borrower);

    require e.msg.value == 0, "no value sent";
    require market.liquidatorGate == 0, "no liquidator gate (see Reverts.spec)";
    require e.block.timestamp < MAX_TIMESTAMP(), "timestamp bounded";
    require market.maturity < MAX_TIMESTAMP(), "maturity bounded";

    // idx 0 not needed as seizedAssets = repaidUnits = 0
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    require debtOf(id, borrower) > 0, "borrower has debt";
    require !liquidationLocked(id, borrower), "not locked";
    require e.block.timestamp > market.maturity || !isHealthy(market, id, borrower), "expired or unhealthy";
    require totalUnits(id) >= debtOf(id, borrower), "totalUnits >= borrower debt (Midnight.spec totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";
    require withdrawable(id) + debtOf(id, borrower) <= MAX_UINT128(), "withdrawable += repaidUnits won't overflow";

    /// Route via the maturity path when available; otherwise via the unhealthy path. The contract's NotLiquidatable
    /// check (Midnight.sol:616-620) gates each path: healthyPath=true ⇒ requires timestamp > maturity;
    /// healthyPath=false ⇒ requires originalDebt > maxDebt (i.e., !isHealthy).
    bool healthyPath = e.block.timestamp > market.maturity;
    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, healthyPath, receiver, 0, data);
    assert !lastReverted;
}

/// SEIZEALL DUAL VARIANTS ///

/// Post-maturity. RCF is deactivated entirely (Midnight.sol:635), so the nonlinear `maxRepaid`
/// formula is never evaluated.
rule liquidatableCanBeLiquidatedSeizeAllPostMaturityDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    uint128 collat = seizeAllDualPreamble(e, market, id, borrower);

    /// healthyPath=true ramps lif (Midnight.sol:641-643): lif = min(maxLif, WAD + (maxLif-WAD)·Δt/TIME_TO_MAX_LIF).
    /// Require Δt ≥ TIME_TO_MAX_LIF unconditionally so that lif resolves to maxLif regardless of `healthy`; this is
    /// what makes the helper `strategyARepaidUnitsAtMaxLif` match the contract's `repaidUnits` computation.
    /// (The unhealthy + within-ramp-window post-maturity case is intentionally out of scope here.)
    require to_mathint(e.block.timestamp) >= to_mathint(market.maturity) + to_mathint(TIME_TO_MAX_LIF()), "lif = maxLif: post-maturity by at least TIME_TO_MAX_LIF";

    /// healthyPath=true: the contract gates NotLiquidatable on `timestamp > maturity` only (Midnight.sol:618), so both
    /// the healthy and unhealthy branches go through here without the unhealthy-only `debt > maxDebt` gate; this also
    /// skips the RCF check inside `if (!healthyPath)` (Midnight.sol:651).
    bytes data;
    liquidate@withrevert(e, market, 0, collat, 0, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

/// Pre-maturity unhealthy, `lltv[0] == WAD`. RCF `maxRepaid` collapses to `type(uint256).max`
/// (Midnight.sol:638-640), so the first RCF disjunct holds trivially.
rule liquidatableCanBeLiquidatedSeizeAllPreMaturityLltvFullDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    uint128 collat = seizeAllDualPreamble(e, market, id, borrower);

    require e.block.timestamp <= market.maturity, "pre-maturity";
    require !isHealthy(market, id, borrower), "unhealthy (required by healthyPath=false branch, Midnight.sol:618)";
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD => RCF denominator vanishes";

    /// healthyPath=false: pre-maturity liquidation goes through the unhealthy branch; lif = maxLif since
    /// healthyPath=false (Midnight.sol:641-643). RCF check is trivialized by lltv == WAD ⇒ maxRepaid = max uint256.
    bytes data;
    liquidate@withrevert(e, market, 0, collat, 0, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// ONEUNIT DUAL VARIANTS ///
/// Witness for "some debt can be repaid" with `repaidUnits = 1` on a 2-collateral market.
/// Split by lif/RCF regime so each sub-case is SMT-tractable.

/// Pre-maturity unhealthy, `lltv[0] == WAD`. RCF `maxRepaid` collapses to `type(uint256).max`.
rule liquidatableCanBeLiquidatedOneUnitPreMaturityLltvFullDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp <= market.maturity, "pre-maturity";
    require !isHealthy(market, id, borrower), "unhealthy";
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD => RCF denominator vanishes";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// Post-maturity, healthy, `timestamp in [maturity, maturity + TIME_TO_MAX_LIF)`.
/// `lif` ramps symbolically in `[WAD, maxLif)`. No RCF check (post-maturity).
rule liquidatableCanBeLiquidatedOneUnitRampedLifDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity";
    require to_mathint(e.block.timestamp) < to_mathint(market.maturity) + to_mathint(TIME_TO_MAX_LIF()), "in ramped window";
    require isHealthy(market, id, borrower), "healthy (otherwise lif is pinned)";

    /// healthyPath=true: post-maturity gating and no RCF check (see SeizeAllPostMaturityDual).
    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

/// Post-maturity, `lif = maxLif` (constant). Either unhealthy or `timestamp >= maturity + TIME_TO_MAX_LIF`.
rule liquidatableCanBeLiquidatedOneUnitPinnedLifDual(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    oneUnitDualPreamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity";
    bool healthy = isHealthy(market, id, borrower);
    require !healthy || to_mathint(e.block.timestamp) >= to_mathint(market.maturity) + to_mathint(TIME_TO_MAX_LIF()), "lif = maxLif: unhealthy, or post-maturity by at least TIME_TO_MAX_LIF";

    /// healthyPath=true: post-maturity gating and no RCF check (see SeizeAllPostMaturityDual).
    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

///////////////////

/// Post-maturity ⇒ use healthyPath=true, which skips the RCF check entirely.
rule liquidatableCanBeLiquidatedRepayAll(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    //uint128 collat = seizeAllDualPreamble(e, market, id, borrower);
    commonDualPreamble(e, market, id, borrower);

    uint256 debt = debtOf(id, borrower);

    bool healthy = isHealthy(market, id, borrower);
    require e.block.timestamp > market.maturity, "post-maturity";
    require !healthy || to_mathint(e.block.timestamp) >= to_mathint(market.maturity) + to_mathint(TIME_TO_MAX_LIF()), "lif = maxLif";

    uint128 collat = collateral(id, borrower, 0);
    require strategyARepaidUnitsAtMaxLif(market, collat) > debt, "Strategy B applicable";

    bytes data;

    // healthyPath=true so RCF check is skipped (it lives inside `if (!healthyPath)`)
    liquidate@withrevert(e, market, 0, 0, debt, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

// @todo Pre-maturity, lltv < WAD, RCF actually engaged is not covered — only the lltv == WAD collapse case. Worth a TODO comment.