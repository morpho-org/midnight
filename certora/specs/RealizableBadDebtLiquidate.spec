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

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
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

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

// Loose (uninterpreted) mulDiv summaries. Because the ghost is a function, equal arguments give equal
// values, so every non-seized collateral term cancels between liquidate's bad-debt loop and the getter.
// The mulDiv values are otherwise constrained only by the near-linear consequences the rules e-match on
// (monotonicity, the getter-form double sub-additivity, and the seize-value bound), each PROVEN over the
// concrete mulDiv in MulDiv.spec. This keeps the heavy nonlinear reasoning out of the liquidate body:
// the solver only instantiates the proven relational facts on the three collateral terms it needs
// (g(c_k), g(c_k - seized), g(seized)), pinning the getter-sum drop without re-deriving nonlinear
// arithmetic. The earlier deterministic (exact-value) summaries were sound but timed out; the earlier
// single-layer loose axioms were tractable but left the g(c_k) - g(c_k - seized) drop unpinned, which
// the solver exploited for a spurious rbd = 21. The double sub-additivity axiom below closes that gap.
function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

// Monotone in the first argument (proven in MulDiv.spec as mulDivMonotoneA).
definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

// Zero collateral values to zero (proven in MulDiv.spec as mulDivZero).
definition axiomUpZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivUp(0, b, d) == 0;

// Getter-form double-mulDivUp sub-additivity (proven in MulDiv.spec as mulDivUpDoubleSubAdditive): for
//   g(x) = mulDivUp(mulDivUp(x, price, ORACLE_PRICE_SCALE), WAD, maxLif),
// g(a) <= g(a - s) + g(s) whenever s <= a. ORACLE_PRICE_SCALE and WAD are pinned to the getter's exact
// constants so this e-matches the getter's/liquidate's ground terms; price (p) and maxLif (L) stay free
// and instantiate to the seized collateral's oracle price and maxLif. Applied to the seized collateral
// (a = c_k, s = seizedAssets) it directly bounds the getter-sum drop g(c_k) - g(c_k - seizedAssets) by
// g(seizedAssets). This is the single relational fact that forbids the ghost from inflating the
// seized-collateral term -- exactly the slack the earlier single-layer axioms left open (the spurious
// g(c_k) - g(c_k - seized) >> g(seized), rbd = 21, counterexample).
definition axiomUpDoubleSubAdditive(mathint a, mathint s, mathint p, mathint L) returns bool = 0 <= s && s <= a && 0 < L => ghostMulDivUp(ghostMulDivUp(a, p, ORACLE_PRICE_SCALE()), WAD(), L) <= ghostMulDivUp(ghostMulDivUp(a - s, p, ORACLE_PRICE_SCALE()), WAD(), L) + ghostMulDivUp(ghostMulDivUp(s, p, ORACLE_PRICE_SCALE()), WAD(), L);

// Getter-form seize-value bound (proven in MulDiv.spec as mulDivSeizeValueBounded): the up-up value
// of the down-down seized collateral never exceeds the repaid units, when seize and value share lif.
definition axiomSeizeValue(mathint r, mathint l, mathint p, mathint sc, mathint w) returns bool = 0 < l && 0 < p && 0 < w && 0 < sc => ghostMulDivUp(ghostMulDivUp(ghostMulDivDown(ghostMulDivDown(r, l, w), sc, p), p, sc), w, l) <= r;

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
// combined rule was heavy enough to be killed server-side. mulDiv is summarized by a loose
// (uninterpreted) ghost, and the nonlinear reasoning is proven once, over the concrete mulDiv, in
// MulDiv.spec; each branch then assumes only the near-linear consequences it e-matches on. The key
// fact is the getter-form double sub-additivity g(c_k) <= g(c_k - seized) + g(seized), which pins the
// seized-collateral drop and closes the spurious rbd = 21 the earlier single-layer axioms allowed.

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

    // The near-linear consequences of the MulDiv lemmas this branch uses are assumed over the loose
    // ghost. The seize-value bound is not needed here: repaidUnits is exactly g(seizedAssets), so the
    // double sub-additivity alone bounds the getter-sum drop g(c_k) - g(c_k - seizedAssets) by the
    // repaid debt drop g(seizedAssets), leaving at most one seized-collateral term's rounding.
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "monotone in first arg (mulDivMonotoneA)";
    require forall mathint b. forall mathint d. axiomUpZero(b, d), "zero collateral values to zero (mulDivZero)";
    require forall mathint a. forall mathint s. forall mathint p. forall mathint L. axiomUpDoubleSubAdditive(a, s, p, L), "getter-form double sub-additivity (mulDivUpDoubleSubAdditive)";

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

    require collateralIndex == 0, "pin seized index to 0 (single collateral) to strip case-split dimensions";
    require market.collateralParams.length == 1, "single collateral: one iteration suffices with the index pin, cheaper for the solver";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits";
    require data.length == 0, "no liquidate callback data (prover performance; matches LiquidationBoundedByLIF.spec)";
    require !postMaturityMode, "non-post-maturity path: the seize factor lif equals maxLif (src/Midnight.sol:685-687)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec.
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "maxLif at least 1x (market-creation invariant)";

    // The near-linear consequences of the MulDiv lemmas are assumed over the loose ghost: the double
    // sub-additivity bounds the getter-sum drop g(c_k) - g(c_k - seizedAssets) by g(seizedAssets), and
    // the seize-value bound closes g(seizedAssets) <= repaidUnits, so the getter-sum drops by at most
    // the repaid debt drop. The nonlinear reasoning is proven once, over concrete mulDiv, in MulDiv.spec
    // (mulDivUpDoubleSubAdditive, mulDivSeizeValueBounded, mulDivMonotoneA, mulDivZero).
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "monotone in first arg (mulDivMonotoneA)";
    require forall mathint b. forall mathint d. axiomUpZero(b, d), "zero collateral values to zero (mulDivZero)";
    require forall mathint a. forall mathint s. forall mathint p. forall mathint L. axiomUpDoubleSubAdditive(a, s, p, L), "getter-form double sub-additivity (mulDivUpDoubleSubAdditive)";
    require forall mathint r. forall mathint l. forall mathint p. forall mathint sc. forall mathint w. axiomSeizeValue(r, l, p, sc, w), "seize-value bound (mulDivSeizeValueBounded)";

    // Ground instances of the derived-seize chain (seizedAssets = src/Midnight.sol:692) so the axioms
    // above close without quantifier search on the loop-internal seized term.
    mathint price = summaryPrice(market.collateralParams[collateralIndex].oracle);
    mathint seizedDerived = ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price);
    mathint gSeized = ghostMulDivUp(ghostMulDivUp(seizedDerived, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    mathint collatK = to_mathint(collateral(id, borrower, collateralIndex));
    mathint gCollatK = ghostMulDivUp(ghostMulDivUp(collatK, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    mathint gCollatKMinusSeized = ghostMulDivUp(ghostMulDivUp(collatK - seizedDerived, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    require gSeized <= to_mathint(repaidUnits), "seize-value bound instance (mulDivSeizeValueBounded)";
    require seizedDerived <= collatK => gCollatK <= gCollatKMinusSeized + gSeized, "double sub-additivity instance (mulDivUpDoubleSubAdditive)";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert realizableBadDebt(market, id, borrower) <= 3;
}
