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

/// Mirrors TIME_TO_MAX_LIF from src/libraries/ConstantsLib.sol.
definition TIME_TO_MAX_LIF() returns uint256 = 15 * 60;

/// SUMMARIES ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

persistent ghost summaryPrice(address) returns uint256;

// Tight bounds proven in MulDiv.spec (mulDivDownRoundsDown, mulDivDownTightBound).
// The monotonicity axiom is derivable from the tight bound but kept explicit so the solver
// doesn't have to divide by `d` (NIA pain point) when bounding `maxDebt += .mulDivDown(lltv, WAD)`.
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivDown(a, b, d) <= a;
}

// Tight bounds proven in MulDiv.spec (mulDivUpRoundsUp, mulDivUpTightBound).
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

/// INVARIANT (proven in CollateralBitmap.spec; assumed here via requireInvariant) ///

strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// HELPERS ///

/// Per-collateral validity (lltv, maxLif, ExactMath bounds) and LIVENESS bounds (oracle > 0, C_i * P_i fits in uint128).
function validCollateralAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) {
    uint256 lltv = market.collateralParams[i].lltv;
    uint256 maxLif = market.collateralParams[i].maxLif;
    require lltv > 0 && lltv <= WAD(), "valid lltv";
    require maxLif >= WAD(), "valid maxLif";
    require lltv < WAD() => to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "ExactMath strict: lltv * maxLif <= WAD*(WAD-1) when lltv<WAD";
    require to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * to_mathint(WAD()), "ExactMath: lltv * maxLif <= WAD^2";

    address oracle = market.collateralParams[i].oracle;
    require summaryPrice(oracle) > 0, "good oracle price";
    require to_mathint(collateral(id, borrower, i)) * to_mathint(summaryPrice(oracle)) <= to_mathint(ORACLE_PRICE_SCALE()) * MAX_UINT128(), "collateral value fits in uint128";
}

/// Two-activated-collateral market with bitmap == 3 (bits 0 and 1 set); matches `loop_iter: 2`.
function dualCollateralSetup(Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 2, "two-collateral market";
    require collateralBitmap(id, borrower) == 3, "bitmap is exactly 3 (bits 0 and 1 set)";

    // Ghost consistency with the real bitmap value 3.
    require summaryGetBit(3, 0) && summaryGetBit(3, 1), "ghost: bits 0 and 1 are set";
    require forall uint256 i. i >= 2 => !summaryGetBit(3, i), "ghost: no other bit is set";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
}

/// Common environment / market preconditions 
function wellBehavedEnv(env e, Midnight.Market market) {
    require e.msg.value == 0, "no value sent";
    require market.liquidatorGate == 0, "no liquidator gate (see Reverts.spec)";
    require to_mathint(e.block.timestamp) < MAX_TIMESTAMP(), "timestamp bounded";
    require to_mathint(market.maturity) < MAX_TIMESTAMP(), "maturity bounded";
}

/// Midnight.spec `totalUnitsEqualsSumNegativeDebtPlusWithdrawable` -> totalUnits >= per-borrower debt.
/// The withdrawable bound is a LIVENESS limit (not currently in Midnight.sol's LIVENESS list).
function feasibleLossAccounting(bytes32 id, address borrower) {
    require totalUnits(id) >= debtOf(id, borrower), "totalUnits >= borrower debt (Midnight.spec totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";
    require to_mathint(withdrawable(id)) + to_mathint(debtOf(id, borrower)) <= MAX_UINT128(), "withdrawable + debt <= MAX_UINT128 (withdrawable += repaidUnits won't overflow)";
}

/// Pins the contract's `lif` (Midnight.sol:625-627) to `maxLif`. Two regimes give lif = maxLif:
///  - the borrower is unhealthy (the ternary's true branch picks `_maxLif`);
///  - the borrower is healthy and at least TIME_TO_MAX_LIF past maturity (the min-clamp picks `_maxLif`).
/// This excludes the [maturity, maturity + TIME_TO_MAX_LIF) window for *still-healthy* borrowers.
function pinLifToMaxLif(env e, Midnight.Market market, bool healthy) {
    require !healthy || to_mathint(e.block.timestamp) >= to_mathint(market.maturity) + to_mathint(TIME_TO_MAX_LIF()), "lif = maxLif: unhealthy, or post-maturity by at least TIME_TO_MAX_LIF";
}

/// Replicates the contract's `repaidUnits = seizedAssets * P / SCALE * WAD / lif`
/// for Strategy A (seizedAssets = collat) when `lif = maxLif` (see pinLifToMaxLif).
function strategyARepaidUnitsAtMaxLif(Midnight.Market market, uint128 collat) returns uint256 {
    address oracle = market.collateralParams[0].oracle;
    uint256 maxLif = market.collateralParams[0].maxLif;
    uint256 step1 = ghostMulDivUp(collat, summaryPrice(oracle), ORACLE_PRICE_SCALE());
    return ghostMulDivUp(step1, WAD(), maxLif);
}

/// RULES ///

/// Sanity baseline: liquidate(0, 0, ...) does not revert on any liquidatable position.
/// Only realizes bad debt; useful as a baseline to confirm the well-behaved environment is correctly set up.
rule liquidateZeroZeroNoRevert(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    dualCollateralSetup(market, id, borrower);
    wellBehavedEnv(e, market);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    require debtOf(id, borrower) > 0, "borrower has debt";
    require !liquidationLocked(id, borrower), "not locked";
    require e.block.timestamp > market.maturity || !isHealthy(market, id, borrower), "expired or unhealthy";
    feasibleLossAccounting(id, borrower);

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, receiver, 0, data);
    assert !lastReverted;
}

rule liquidatableCanBeLiquidatedSeizeAll(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    dualCollateralSetup(market, id, borrower);
    wellBehavedEnv(e, market);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    feasibleLossAccounting(id, borrower);

    require !liquidationLocked(id, borrower), "not locked";
    uint256 debt = debtOf(id, borrower);
    require debt > 0, "borrower has debt";

    bool healthy = isHealthy(market, id, borrower);
    require e.block.timestamp > market.maturity || !healthy, "expired or unhealthy";

    /// RCF bypass for the pre-maturity unhealthy regime (post-maturity has RCF deactivated).
    require e.block.timestamp > market.maturity || market.rcfThreshold == max_uint256 || market.collateralParams[0].lltv == WAD(), "RCF check bypassed (pre-maturity)";

    pinLifToMaxLif(e, market, healthy);

    /// `collat > 0` follows from the index-0 invariant + `summaryGetBit(3, 0)`.
    uint128 collat = collateral(id, borrower, 0);

    /// Strategy A applicable: the contract-computed repaidUnits (with lif = maxLif) fits in debt.
    require strategyARepaidUnitsAtMaxLif(market, collat) <= debt, "Strategy A applicable";

    bytes data;
    liquidate@withrevert(e, market, 0, collat, 0, borrower, receiver, 0, data);
    assert !lastReverted;
}

rule liquidatableCanBeLiquidatedRepayAll(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    dualCollateralSetup(market, id, borrower);
    wellBehavedEnv(e, market);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    feasibleLossAccounting(id, borrower);

    require !liquidationLocked(id, borrower), "not locked";
    uint256 debt = debtOf(id, borrower);
    require debt > 0, "borrower has debt";

    bool healthy = isHealthy(market, id, borrower);
    require e.block.timestamp > market.maturity || !healthy, "expired or unhealthy";

    require e.block.timestamp > market.maturity || market.rcfThreshold == max_uint256 || market.collateralParams[0].lltv == WAD(), "RCF check bypassed (pre-maturity)";

    pinLifToMaxLif(e, market, healthy);

    /// `collat > 0` follows from the index-0 invariant + `summaryGetBit(3, 0)`.
    uint128 collat = collateral(id, borrower, 0);

    /// Strategy B applicable: Strategy A would over-repay, so the contract's choice is repay-all.
    require strategyARepaidUnitsAtMaxLif(market, collat) > debt, "Strategy B applicable";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, debt, borrower, receiver, 0, data);
    assert !lastReverted;
}

/// Witness for "some debt can be repaid": pass `repaidUnits = 1` (the minimum positive amount).
/// Covers the regimes uncovered by the seize-all/repay-all rules:
///  - pre-maturity unhealthy with finite rcfThreshold and lltv < WAD (RCF caps the per-call repay),
///  - post-maturity healthy in [maturity, maturity + TIME_TO_MAX_LIF) (ramped lif).
rule liquidatableCanBeLiquidatedOneUnit(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);

    dualCollateralSetup(market, id, borrower);
    wellBehavedEnv(e, market);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    feasibleLossAccounting(id, borrower);

    require !liquidationLocked(id, borrower), "not locked";
    require debtOf(id, borrower) > 0, "borrower has debt";
    require e.block.timestamp > market.maturity || !isHealthy(market, id, borrower), "expired or unhealthy";

    /// LIVENESS: `seizedAssets = mulDivDown(mulDivDown(1, lif, WAD), SCALE, P) <= maxLif * SCALE / (WAD * P)`
    /// for any `lif in [WAD, maxLif]`. Bound this by `collat 0` so the seizure fits.
    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    require to_mathint(maxLif) * to_mathint(ORACLE_PRICE_SCALE()) <= to_mathint(collat) * to_mathint(WAD()) * to_mathint(summaryPrice(oracle)), "LIVENESS: collat 0 absorbs the 1-unit seizure at maxLif";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, receiver, 0, data);
    assert !lastReverted;
}
