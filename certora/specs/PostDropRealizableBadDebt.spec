// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Property: liquidating ahead of an oracle price drop cannot worsen the post-drop realizable bad debt.
//
// Concretely: liquidate runs at the pre-drop call-time price p (the price it reads from the oracle),
// while realizable bad debt is *measured* at a DROPPED price p' <= p. The claim is
//   R' <= R,
// where R = do-nothing post-drop rbd (measured at p' before liquidate) and R' = post-liquidate
// post-drop rbd (measured at p' after liquidate). I.e. having liquidated first never leaves MORE
// realizable bad debt at the dropped price than doing nothing.
//
// Measurement at the decoupled price p' uses realizableBadDebtAtPrice (certora/helpers/MidnightWrapper.sol),
// a verbatim structural copy of the realizableBadDebt getter that values each active collateral at an
// explicitly passed price instead of reading IOracle(...).price(). Per active collateral c it subtracts
//   g_x(c) = mulDivUp(mulDivUp(c, x, ORACLE_PRICE_SCALE), WAD, maxLif)
// where x is the passed measurement price. The iterated zeroFloorSub equals zeroFloorSub(debt, sum of
// terms), so rbd is monotone: more debt removed or less coverage removed cannot increase it.
//
// Proof (single seized collateral c_k -> c_k - seized, debt reduced by >= repaidUnits):
//   coverage-removed at p' = g_{p'}(c_k) - g_{p'}(c_k - seized)
//                          <= g_{p'}(seized)         [getter-form double sub-additivity, at p']
//                          <= g_{p}(seized)          [getter-form price monotonicity, p' <= p]
//                          <= repaidUnits            [seize-value bound at p / repaid = g_p(seized)]
//                          <= debt-removed.
// Since coverage-removed <= debt-removed, zeroFloorSub monotonicity gives R' <= R with no slack.
//
// This reuses #1079's seize-value bound and double sub-additivity lemmas, and adds the price
// monotonicity of the getter term (g is non-decreasing in the price argument), which is what bridges
// the p'-measured coverage drop to the p-priced seize/repay logic liquidate actually executes.
//
// Restricted, like the isolated liquidate leg it builds on, to the non-post-maturity path
// (require !postMaturityMode, where lif == maxLif, src/Midnight.sol:685-687), a single seized
// collateral, and split along liquidate's exclusive-input branch (repaidUnits == 0 || seizedAssets == 0).

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

    // Per-callee constant price (no price update): this is the call-time price p that liquidate reads.
    // The measurement price p' is decoupled from it, passed explicitly to realizableBadDebtAtPrice.
    function _.price() external => summaryPrice[calledContract] expect(uint256);

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

persistent ghost mapping(address => uint256) summaryPrice;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

// Loose (uninterpreted) mulDiv summaries, identical to RealizableBadDebtLiquidate.spec: because the ghost
// is a function, equal arguments give equal values, so every unchanged collateral term is identical
// between the before-getter and the after-getter measurements. The mulDiv values are otherwise
// constrained only by the near-linear consequences the rule e-matches on (monotonicity in each argument,
// getter-form double sub-additivity, and the seize-value bound), each PROVEN over the concrete mulDiv in
// MulDiv.spec. This keeps the heavy nonlinear reasoning out of the liquidate body.
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

// Monotone in the second argument (proven in MulDiv.spec as mulDivMonotoneB). Applied to the inner
// mulDivUp(collateral, price, ORACLE_PRICE_SCALE): dropping the price argument from p to p' <= p cannot
// grow the inner value, and (with axiomUpMonotoneA on the outer layer) cannot grow the getter term g.
definition axiomUpMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivUp(a, b1, d) <= ghostMulDivUp(a, b2, d);

// Zero collateral values to zero (proven in MulDiv.spec as mulDivZero). Also covers the seized-collateral
// bitmap-clear path: when the seize empties the collateral, the after-getter drops the term and its
// value is g(0) = 0.
definition axiomUpZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivUp(0, b, d) == 0;

// Getter-form double-mulDivUp sub-additivity (proven in MulDiv.spec as mulDivUpDoubleSubAdditive): for
//   g_x(c) = mulDivUp(mulDivUp(c, x, ORACLE_PRICE_SCALE), WAD, maxLif),
// g_x(a) <= g_x(a - s) + g_x(s) whenever s <= a. ORACLE_PRICE_SCALE and WAD are pinned to the getter's
// exact constants so this e-matches the getter's ground terms; the price (here the measurement price p')
// and maxLif stay free. Applied at p' to the seized collateral (a = c_k, s = seized) it bounds the
// p'-measured coverage drop g_{p'}(c_k) - g_{p'}(c_k - seized) by g_{p'}(seized).
definition axiomUpDoubleSubAdditive(mathint a, mathint s, mathint p, mathint L) returns bool = 0 <= s && s <= a && 0 < L => ghostMulDivUp(ghostMulDivUp(a, p, ORACLE_PRICE_SCALE()), WAD(), L) <= ghostMulDivUp(ghostMulDivUp(a - s, p, ORACLE_PRICE_SCALE()), WAD(), L) + ghostMulDivUp(ghostMulDivUp(s, p, ORACLE_PRICE_SCALE()), WAD(), L);

// Getter-form seize-value bound (proven in MulDiv.spec as mulDivSeizeValueBounded): the up-up value
// (at the call-time price p) of the down-down seized collateral never exceeds the repaid units, when
// seize and value share lif. This closes g_p(seized) <= repaidUnits on the repaid-input branch.
definition axiomSeizeValue(mathint r, mathint l, mathint p, mathint sc, mathint w) returns bool = 0 < l && 0 < p && 0 < w && 0 < sc => ghostMulDivUp(ghostMulDivUp(ghostMulDivDown(ghostMulDivDown(r, l, w), sc, p), p, sc), w, l) <= r;

// Dropped-price seize-value bound (proven in MulDiv.spec as mulDivSeizeValueAtDroppedPriceBounded): the
// up-up value at the DROPPED price pDrop (<= call-time price p) of the down-down seized collateral never
// exceeds the repaid units r. Composes axiomSeizeValue (bound at p) with price monotonicity in one fact,
// closing g_{p'}(seized) <= repaidUnits directly on the repaid-input branch.
definition axiomSeizeValueAtDroppedPrice(mathint r, mathint l, mathint p, mathint sc, mathint w, mathint pDrop) returns bool = 0 < l && 0 < p && 0 < w && 0 < sc && 0 <= pDrop && pDrop <= p => ghostMulDivUp(ghostMulDivUp(ghostMulDivDown(ghostMulDivDown(r, l, w), sc, p), pDrop, sc), w, l) <= r;

/// INVARIANTS ///

// Proven in CollateralBitmap.spec; assumed here via requireInvariant (not re-proven in this spec).
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// RULES ///

// Post-price-drop realizable bad debt cannot increase from liquidating first: with liquidate executed at
// the call-time price p and realizable bad debt measured at a dropped price p' (= pDrop) <= p, the
// post-liquidate p'-rbd R' is at most the do-nothing p'-rbd R. Restricted to !postMaturityMode
// (lif == maxLif) and split along liquidate's exclusive-input branch, matching the isolated liquidate leg.

// Seized-assets-input branch (repaidUnits == 0): liquidate derives the repaid debt drop
//   repaidUnits = mulDivUp(mulDivUp(seizedAssets, p, ORACLE_PRICE_SCALE), WAD, lif) = g_p(seizedAssets)
// (src/Midnight.sol:690). The p'-measured coverage drop g_{p'}(c_k) - g_{p'}(c_k - seizedAssets) is at
// most g_{p'}(seizedAssets) (sub-additivity at p'), and price monotonicity gives g_{p'}(seizedAssets) <=
// g_p(seizedAssets) = the repaid debt drop. So coverage removed at p' <= debt removed, and zeroFloorSub
// monotonicity yields R' <= R. No seize-value bound is needed here (repaid is literally the getter term).
rule postDropRbdLiquidateNonIncreaseSeizeInput(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, uint256 pDrop) {
    bytes32 id = summaryToId(market);

    require repaidUnits == 0, "seized-assets-input branch: repaidUnits is derived from seizedAssets (src/Midnight.sol:690)";

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

    uint256 price = summaryPrice[market.collateralParams[collateralIndex].oracle];
    require pDrop <= price, "the measurement price p' is a dropped price: p' <= call-time price p";

    // Near-linear consequences of the MulDiv lemmas, assumed over the loose ghost (each proven in
    // MulDiv.spec): monotonicity in each argument (mulDivMonotoneA/B) supplies the price bridge
    // g_{p'}(seized) <= g_p(seized), and double sub-additivity (mulDivUpDoubleSubAdditive) bounds the
    // p'-coverage drop by g_{p'}(seized). axiomUpZero (mulDivZero) covers the emptied-collateral term.
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "monotone in first arg (mulDivMonotoneA)";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomUpMonotoneB(a, b1, b2, d), "monotone in second arg (mulDivMonotoneB)";
    require forall mathint b. forall mathint d. axiomUpZero(b, d), "zero collateral values to zero (mulDivZero)";
    require forall mathint a. forall mathint s. forall mathint p. forall mathint L. axiomUpDoubleSubAdditive(a, s, p, L), "getter-form double sub-additivity (mulDivUpDoubleSubAdditive)";

    // Ground instances on the seized collateral so the axioms close without deep quantifier search.
    // seized == seizedAssets here (input). g_p(seizedAssets) is exactly the repaid debt drop (line 690).
    mathint innerSeizedDrop = ghostMulDivUp(seizedAssets, pDrop, ORACLE_PRICE_SCALE());
    mathint innerSeizedP = ghostMulDivUp(seizedAssets, price, ORACLE_PRICE_SCALE());
    mathint gSeizedDrop = ghostMulDivUp(innerSeizedDrop, WAD(), maxLif);
    mathint gSeizedP = ghostMulDivUp(innerSeizedP, WAD(), maxLif);
    mathint collatK = to_mathint(collateral(id, borrower, collateralIndex));
    mathint gCollatKDrop = ghostMulDivUp(ghostMulDivUp(collatK, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    mathint gCollatKMinusSeizedDrop = ghostMulDivUp(ghostMulDivUp(collatK - seizedAssets, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    // Price bridge (mulDivMonotoneB on the inner layer, since pDrop <= price, then mulDivMonotoneA on the
    // outer layer). Sub-additivity at p' bounds the coverage drop by g_{p'}(seizedAssets).
    require gSeizedDrop <= gSeizedP, "price bridge: g_{p'}(seized) <= g_p(seized) (mulDivMonotoneB then mulDivMonotoneA)";
    require to_mathint(seizedAssets) <= collatK => gCollatKDrop <= gCollatKMinusSeizedDrop + gSeizedDrop, "double sub-additivity instance at p' (mulDivUpDoubleSubAdditive)";

    // scenario 1: price drops, then realize bad debt
    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint R = realizableBadDebt(market, id, borrower);

    // scenario 2: liquidate at initial (higher) price
    // then price drop, realize remaining debt.
    summaryPrice[market.collateralParams[collateralIndex].oracle] = price;

    mathint R1 = realizableBadDebt(market, id, borrower);
    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint R2 = realizableBadDebt(market, id, borrower);

    assert R1 + R2 <= R;
}

// Repaid-units-input branch (seizedAssets == 0): liquidate derives the seized collateral
//   seizedAssets = mulDivDown(mulDivDown(repaidUnits, lif, WAD), ORACLE_PRICE_SCALE, p)
// (src/Midnight.sol:692). Sub-additivity at p' bounds the p'-coverage drop by g_{p'}(seized), price
// monotonicity gives g_{p'}(seized) <= g_p(seized), and the seize-value bound closes g_p(seized) <=
// repaidUnits (the repaid debt drop). So coverage removed at p' <= debt removed, and zeroFloorSub
// monotonicity yields R' <= R. This is the harder case: it exercises both the seize (mulDivDown) and
// value (mulDivUp) chains, plus the price bridge.
rule postDropRbdLiquidateNonIncreaseRepaidInput(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, uint256 pDrop) {
    bytes32 id = summaryToId(market);

    require seizedAssets == 0, "repaid-units-input branch: seizedAssets is derived from repaidUnits (src/Midnight.sol:692)";

    // single collateral: solver-tractability scope; multi-collateral follows from K=0 subadditivity (non-seized terms are identical before/after)
    require market.collateralParams.length == 1, "restrict collateralParams for loop tractability";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits";
    require data.length == 0, "no liquidate callback data (prover performance; matches LiquidationBoundedByLIF.spec)";
    require !postMaturityMode, "non-post-maturity path: the seize factor lif equals maxLif (src/Midnight.sol:685-687)";

    // Soundness: nonZeroCollateralsAreActivated is proven in CollateralBitmap.spec.
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "maxLif at least 1x (market-creation invariant)";

    uint256 price = summaryPrice[market.collateralParams[collateralIndex].oracle];
    require price > 0, "call-time price positive (liquidate divides by it at src/Midnight.sol:692)";
    require pDrop <= price, "the measurement price p' is a dropped price: p' <= call-time price p";

    // Near-linear consequences of the MulDiv lemmas, assumed over the loose ghost (each proven in
    // MulDiv.spec): the double sub-additivity bounds the p'-coverage drop by g_{p'}(seized), and the
    // dropped-price seize-value bound closes g_{p'}(seized) <= repaidUnits in one step (no separate price
    // bridge / call-time bound to chain). axiomUpZero covers the emptied-collateral term.
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "monotone in first arg (mulDivMonotoneA)";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomUpMonotoneB(a, b1, b2, d), "monotone in second arg (mulDivMonotoneB)";
    require forall mathint b. forall mathint d. axiomUpZero(b, d), "zero collateral values to zero (mulDivZero)";
    require forall mathint a. forall mathint s. forall mathint p. forall mathint L. axiomUpDoubleSubAdditive(a, s, p, L), "getter-form double sub-additivity (mulDivUpDoubleSubAdditive)";
    require forall mathint r. forall mathint l. forall mathint p. forall mathint sc. forall mathint w. forall mathint pd. axiomSeizeValueAtDroppedPrice(r, l, p, sc, w, pd), "dropped-price seize-value bound (mulDivSeizeValueAtDroppedPriceBounded)";

    // Ground instances of the derived-seize chain (seizedAssets = src/Midnight.sol:692) so the axioms
    // close without quantifier search on the loop-internal seized term.
    mathint seizedDerived = ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price);
    mathint innerSeizedDrop = ghostMulDivUp(seizedDerived, pDrop, ORACLE_PRICE_SCALE());
    mathint gSeizedDrop = ghostMulDivUp(innerSeizedDrop, WAD(), maxLif);
    mathint collatK = to_mathint(collateral(id, borrower, collateralIndex));
    mathint gCollatKDrop = ghostMulDivUp(ghostMulDivUp(collatK, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    mathint gCollatKMinusSeizedDrop = ghostMulDivUp(ghostMulDivUp(collatK - seizedDerived, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    // Single-step dropped-price seize-value bound: the p'-valued derived seize is at most repaidUnits
    // (mulDivSeizeValueAtDroppedPriceBounded), collapsing the former call-time-bound + price-bridge chain.
    // Sub-additivity at p' then bounds the coverage drop by g_{p'}(seized).
    require gSeizedDrop <= to_mathint(repaidUnits), "dropped-price seize-value bound instance (mulDivSeizeValueAtDroppedPriceBounded)";
    require seizedDerived <= collatK => gCollatKDrop <= gCollatKMinusSeizedDrop + gSeizedDrop, "double sub-additivity instance at p' (mulDivUpDoubleSubAdditive)";

    // scenario 1: price drops, then realize bad debt
    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint R = realizableBadDebt(market, id, borrower);

    // scenario 2: liquidate at initial (higher) price
    // then price drop, realize remaining debt.
    summaryPrice[market.collateralParams[collateralIndex].oracle] = price;

    mathint R1 = realizableBadDebt(market, id, borrower);
    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint R2 = realizableBadDebt(market, id, borrower);

    assert R1 + R2 <= R;
}
