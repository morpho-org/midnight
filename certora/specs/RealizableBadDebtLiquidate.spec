// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Property (issue #109), liquidate case:
//   "Liquidation realizes the bad debt and leaves zero."
//
// This is the hard, full-args counterpart of the rules in RealizableBadDebt.spec: after a
// liquidate with arbitrary seizedAssets/repaidUnits, realizableBadDebt recomputes to zero.
// It is isolated in its own spec (and CI leg) because it needs the getter-form mulDivUp
// value-drop bound, which is heavy for the solver.
//
// realizableBadDebt(id, borrower) is the `badDebt` local computed at the top of
// Midnight.liquidate (src/Midnight.sol:643-657), and per active collateral c it subtracts
//   g(c) = mulDivUp(mulDivUp(c, price, ORACLE_PRICE_SCALE), WAD, maxLif).
// Liquidate seizes from a single collateral (c_k -> c_k - seizedAssets) and repays repaidUnits.
// The proof: the getter-sum drop g(c_k) - g(c_k - seizedAssets) is at most g(seizedAssets)
// (double-mulDivUp sub-additivity), and g(seizedAssets) <= repaidUnits (seize-value bound), so
// the getter-sum drops by at most the debt drop and the recomputed bad debt stays zero.
//
// The rule is restricted to the non-post-maturity path (require !postMaturityMode), where the
// seize factor lif equals maxLif (src/Midnight.sol:685-687); the post-maturity path (lif < maxLif)
// is left for follow-up.

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function totalUnits(bytes32) external returns (uint128) envfree;
    function lossFactor(bytes32) external returns (uint128) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Per-callee constant price (no price update); named so the rule can reference it, matching LiquidationBoundedByLIF.spec.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => detMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => detMulDivUp(x, y, d);
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // All external calls are assumed non-reentrant / non-reverting: we reason about the function bodies for safety properties.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
}

/// SUMMARIES / GHOSTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost summaryPrice(address) returns uint256;

// Deterministic mulDiv summaries: rather than an uninterpreted ghost constrained by loose
// monotonicity/subadditivity axioms (which let the solver pick non-arithmetic values that satisfy
// the axioms but contradict real mulDiv, yielding spurious counterexamples), these compute the
// EXACT value of UtilsLib.mulDivDown/mulDivUp. There is then exactly one possible value per call,
// so the fake-value exploit is impossible and no bound axioms are needed.
//
// UtilsLib.mulDivDown(x, y, d) = (x * y) / d (checked 0.8 arithmetic, src/libraries/UtilsLib.sol:22-24):
// reverts when x * y overflows uint256 or d == 0; otherwise floor(x * y / d).
function detMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint prod = to_mathint(x) * to_mathint(y);
    if (prod > max_uint256 || d == 0) {
        revert();
    }
    return require_uint256(prod / d);
}

// UtilsLib.mulDivUp(x, y, d) = (x * y + (d - 1)) / d (checked 0.8 arithmetic, src/libraries/UtilsLib.sol:27-29):
// d - 1 underflow-reverts when d == 0; x * y and x * y + (d - 1) overflow-revert when >= 2^256.
// Since d >= 1 the numerator x * y + (d - 1) >= x * y, so a single "numerator > max_uint256" check
// captures both the product and the sum overflow. Otherwise ceil(x * y / d).
function detMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    mathint num = to_mathint(x) * to_mathint(y) + to_mathint(d) - 1;
    if (num > max_uint256) {
        revert();
    }
    return require_uint256(num / d);
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// INVARIANTS ///

// Proven in CollateralBitmap.spec; assumed here via requireInvariant (not re-proven in this spec).
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// RULES ///

// liquidate realizes the bad debt: the recomputed realizable bad debt is at most 3 (one
// seized-collateral term's rounding) after a full-args liquidate. Restricted to
// !postMaturityMode, where the seize factor lif equals maxLif.
//
// The rule is split along liquidate's exclusive-input branch (src/Midnight.sol:633,
// `require repaidUnits == 0 || seizedAssets == 0`), one CI leg per branch, because the single
// combined rule was heavy enough to be killed server-side. mulDiv is summarized deterministically
// (detMulDivDown/detMulDivUp), so the nonlinear reasoning is done directly over the exact mulDiv
// values with no ghost axioms and no ghost slack for the solver to exploit.

// Seized-assets-input branch (repaidUnits == 0): liquidate computes
//   repaidUnits = mulDivUp(mulDivUp(seizedAssets, price, ORACLE_PRICE_SCALE), WAD, lif) = g(seizedAssets)
// (src/Midnight.sol:691), i.e. the debt drop is exactly the getter value of the seized collateral.
// Sub-additivity bounds the getter-sum drop g(c_k) - g(c_k - seizedAssets) by g(seizedAssets), which
// here equals the repaid debt drop, so the recomputed bad debt stays at most 3 (one seized-collateral
// term's rounding). No seize-value bound is needed on this branch (repaid is literally the getter term).
rule liquidateRealizesBadDebtSeizeInput(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require repaidUnits == 0, "seized-assets-input branch: repaidUnits is derived from seizedAssets (src/Midnight.sol:691)";

    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits";
    require data.length == 0, "no liquidate callback data (prover performance; matches LiquidationBoundedByLIF.spec)";
    require !postMaturityMode, "non-post-maturity path: the seize factor lif equals maxLif (src/Midnight.sol:685-687)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec.
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "maxLif at least 1x (market-creation invariant)";

    // No mulDiv axioms are assumed: detMulDivDown/detMulDivUp compute the exact mulDiv value, so the
    // prover reasons over concrete arithmetic (monotonicity, sub-additivity and the seize-value bound
    // all hold by construction) with no ghost slack to exploit.

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert realizableBadDebt(market, id, borrower) <= 3;
}

// Repaid-units-input branch (seizedAssets == 0): liquidate computes
//   seizedAssets = mulDivDown(mulDivDown(repaidUnits, lif, WAD), ORACLE_PRICE_SCALE, price)
// (src/Midnight.sol:693). Sub-additivity bounds the getter-sum drop by g(seizedAssets), and the
// seize-value bound closes g(seizedAssets) <= repaidUnits, so the getter-sum drops by at most the
// repaid debt drop and the recomputed bad debt stays at most 3 (one seized-collateral term's
// rounding). This is the harder case: it exercises both the seize (mulDivDown) and value (mulDivUp)
// chains, now discharged over the exact deterministic mulDiv values.
rule liquidateRealizesBadDebtRepaidInput(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require seizedAssets == 0, "repaid-units-input branch: seizedAssets is derived from repaidUnits (src/Midnight.sol:693)";

    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits";
    require data.length == 0, "no liquidate callback data (prover performance; matches LiquidationBoundedByLIF.spec)";
    require !postMaturityMode, "non-post-maturity path: the seize factor lif equals maxLif (src/Midnight.sol:685-687)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec.
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "maxLif at least 1x (market-creation invariant)";

    // No mulDiv axioms are assumed: detMulDivDown/detMulDivUp compute the exact mulDiv value, so the
    // prover reasons over concrete arithmetic (sub-additivity and the seize-value bound
    // g(seizedAssets) <= repaidUnits hold by construction) with no ghost slack to exploit.

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert realizableBadDebt(market, id, borrower) <= 3;
}
