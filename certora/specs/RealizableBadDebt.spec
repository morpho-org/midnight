// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Property (issue #109):
//   "realizableBadDebt cannot increase (without a price update). Liquidation is a special
//    case: it is not enough that it does not increase realizableBadDebt, it also realizes it."
//
// realizableBadDebt(id, borrower) is the `badDebt` local computed at the top of
// Midnight.liquidate (src/Midnight.sol:643-657):
//   zeroFloorSub(debt, SUM over active-collateral i of ceil(ceil(col_i*price_i/OPS)*WAD/maxLif_i)).
// It is exposed by MidnightWrapper.realizableBadDebt(market, id, borrower), whose loop is a
// verbatim copy of that production loop so the prover can equate the getter with liquidate's
// inlined computation (the same "match the spec's check against the code" trick used in
// Healthiness.spec for isHealthy()).
//
// "Without a price update" is modelled by summarizing _.price() as PER_CALLEE_CONSTANT: each
// oracle returns a single deterministic value fixed across the whole rule, so the before- and
// after-snapshots of the getter (and liquidate's own loop) all observe the same prices.

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // The getter added to MidnightWrapper. Modelled envfree exactly like isHealthyNoBitmap,
    // which also takes a Market and calls IOracle.price(); envfree works because price() is
    // summarized and the body has no env dependency.
    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;

    // Envfree public getters actually used by the rules.
    function debt(bytes32, address) external returns (uint128) envfree;
    function totalUnits(bytes32) external returns (uint128) envfree;
    function lossFactor(bytes32) external returns (uint128) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // "Without price update": each oracle's price is a deterministic constant for the whole
    // rule, so it is identical across the before/after evaluations of the getter and liquidate.
    function _.price() external => PER_CALLEE_CONSTANT;

    // toId is linked to state via the deterministic (and, under optimistic_hashing, injective)
    // keccak hash of the market, mirroring LossFactor.spec. liquidate's internal touchMarket ->
    // toId(market) therefore yields the same id used to query the getter and the getters.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;

    // mulDiv summarized by deterministic ghosts so both bad-debt evaluations use identical
    // arithmetic. Axioms are the subset of the MulDiv.spec bundle used by Healthiness.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // maxLif recomputed on the fly from (lltv, liquidationCursor); summarized deterministically
    // like Healthiness.spec:30. The bound lltv*maxLif <= WAD*WAD is required in the rules.
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // Token transfers bypassed (LossFactor.spec style). All other external calls (oracle aside)
    // are assumed non-reentrant / non-reverting: we reason about the function bodies, and
    // liquidate is non-reentrant.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // take's external staticcall view gates/ratifier. These run after touchMarket and cannot
    // affect realizableBadDebt, but left unresolved they trigger full-storage HAVOCs that time
    // the parametric rule out to UNKNOWN, so summarize them NONDET (sound: staticcall views).
    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
}

/// SUMMARIES / GHOSTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

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

// toId summary: deterministic hash of the market (injective under optimistic_hashing).
function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/* Axioms proved in MulDiv.spec / ExactMath.spec (same bundle as Healthiness.spec). */

/* proved in mulDivZero */
definition axiomDownZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivDown(0, b, d) == 0;

/* proved in mulDivMonotoneA */
definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);

definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

/* proved in mulDivMonotoneB */
definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);

/* proved in mulDivMonotoneD */
definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);

/* proved in ExactMath.spec (mulDivLifLLTV): the healthy => rbd == 0 bridge */
definition axiomLifLLTV(mathint a, mathint lif, mathint lltv) returns bool = a >= 0 && lltv * lif <= WAD() * WAD() => ghostMulDivUp(a, lltv, WAD()) <= ghostMulDivUp(a, WAD(), lif);

/// RULES ///

// (i) PARAMETRIC: no non-liquidate, non-view function may INCREASE realizableBadDebt.
//   liquidate is excluded (handled by rule (ii)); view functions cannot mutate state.
//   "Without price update" is enforced by the PER_CALLEE_CONSTANT price summary.
//
// FLAG (needs prover iteration): for debt-increasing functions (borrow) or collateral-removing
//   functions (withdrawCollateral), rbd does not increase only because those functions re-check
//   isHealthy(), and healthy => rbd == 0 (issue-#109 analysis part C). That bridge relies on
//   the maxLif<=1/lltv require + axiomLifLLTV below. If the prover cannot connect f's own health check to the
//   getter here (this rule does NOT re-assert isHealthy), those methods may report violations
//   and this rule likely needs the Healthiness.spec global-market + isHealthyOrLiquidationLocked
//   machinery grafted in (fix a global market/id/borrower, assert healthy-or-locked after f).
rule realizableBadDebtCannotIncrease(env e, method f, calldataarg args, Midnight.Market market, address borrower) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    bytes32 id = summaryToId(market);

    // Bound the collateral loop like Healthiness.spec does (globalMarketCollateralLength <= 2)
    // so loop_iter = 2 fully unrolls both getter evaluations.
    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";

    // mulDiv monotonicity bundle (threaded via require forall, as Healthiness.spec does).
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require forall mathint a. forall mathint lif. forall mathint lltv. axiomLifLLTV(a, lif, lltv), "axiom";
    require forall mathint b. forall mathint d. axiomDownZero(b, d), "axiom";

    // maxLif <= 1/lltv for every (lltv, cursor); proved in lifTimesLltvIsLessThanOrEqualToOne
    // (ExactMath.spec). Needed for the healthy => realizableBadDebt == 0 bridge.
    require forall uint256 lltv. forall uint256 cursor. lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "maxLif is at most 1/lltv";

    uint256 rbdBefore = realizableBadDebt(market, id, borrower);

    f(e, args);

    uint256 rbdAfter = realizableBadDebt(market, id, borrower);

    assert rbdAfter <= rbdBefore, "no non-liquidate function increases realizable bad debt";
}

// (ii) LIQUIDATE special case: liquidate does not increase realizableBadDebt AND, when there was
//   bad debt (rbdBefore > 0), it realizes it: totalUnits drops by EXACTLY rbdBefore and lossFactor
//   strictly increases.
//
// The exactness rests on rbdBefore == liquidate's own `badDebt` local: the getter and liquidate's
//   inlined loop run over the same PRE-call state with the same price / maxLif / mulDiv ghosts and
//   bitmap summaries, so the prover equates them. liquidate then does, at src/Midnight.sol:667-673,
//   `_position.debt -= badDebt` and `_marketState.totalUnits -= badDebt`; the seize/repay block
//   (682-715) never touches totalUnits or lossFactor, so the drop is exactly badDebt.
rule liquidateRealizesBadDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";

    // Well-formedness the realization arithmetic assumes (mirrors LossFactor.spec).
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits (totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";

    // mulDiv monotonicity bundle (threaded via require forall, as Healthiness.spec does).
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require forall mathint a. forall mathint lif. forall mathint lltv. axiomLifLLTV(a, lif, lltv), "axiom";
    require forall mathint b. forall mathint d. axiomDownZero(b, d), "axiom";
    require forall uint256 lltv. forall uint256 cursor. lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "maxLif is at most 1/lltv";

    uint256 rbdBefore = realizableBadDebt(market, id, borrower);
    uint256 totalUnitsBefore = totalUnits(id);
    uint128 lossFactorBefore = lossFactor(id);

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    uint256 rbdAfter = realizableBadDebt(market, id, borrower);

    // (a) liquidate never increases realizable bad debt.
    // FLAG: this direction recomputes rbd over POST state (debt reduced by badDebt and possibly
    //   repaidUnits, collateral seized). It leans on the mulDiv monotonicity axioms and is the
    //   fiddly part; if it does not go through, first prove it for the pure-realization path
    //   (seizedAssets == 0 && repaidUnits == 0), as LossFactor.spec's liquidate rule does.
    assert rbdAfter <= rbdBefore, "liquidate does not increase realizable bad debt";

    // (b) if there was bad debt, it is realized in totalUnits by EXACTLY rbdBefore.
    assert rbdBefore > 0 => to_mathint(totalUnits(id)) == to_mathint(totalUnitsBefore) - to_mathint(rbdBefore), "bad debt realized: totalUnits drops by exactly rbdBefore";

    // (c) and lossFactor strictly increases.
    // FLAG: strict `>` may need a strict-monotonicity axiom for mulDivDown that is not in the
    //   bundle above (the ghost only carries non-strict monotonicity). LossFactor.spec proves the
    //   weaker `lossFactor changed <=> totalUnits decreased`. If strictness fails, fall back to
    //   `lossFactor(id) != lossFactorBefore`.
    assert rbdBefore > 0 => lossFactor(id) > lossFactorBefore, "lossFactor strictly increases when bad debt is realized";
}
