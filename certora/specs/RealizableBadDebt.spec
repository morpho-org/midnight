// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Property (issue #109):
//   "realizableBadDebt cannot increase (without a price update). Liquidation is a special
//    case: it should realize the bad debt and leave zero."
//
// realizableBadDebt(id, borrower) is the `badDebt` local computed at the top of
// Midnight.liquidate (src/Midnight.sol:643-657).
//
// "Without a price update" is modelled by summarizing _.price() as PER_CALLEE_CONSTANT.

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
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    function _.price() external => PER_CALLEE_CONSTANT;

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

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);

definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);

definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);

definition axiomDownZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivDown(0, b, d) == 0;

definition axiomUpGeqDown(mathint a, mathint b, mathint d) returns bool = d > 0 => ghostMulDivUp(a, b, d) >= ghostMulDivDown(a, b, d);

definition axiomLifLLTV(mathint a, mathint lif, mathint lltv) returns bool = a >= 0 && lltv * lif <= WAD() * WAD() => ghostMulDivUp(a, lltv, WAD()) <= ghostMulDivUp(a, WAD(), lif);

/// RULES ///

// No non-liquidate, non-view function may increase realizableBadDebt of an arbitrary position.
// take and withdrawCollateral both require the acted-on borrower healthy afterwards, and a healthy
// borrower has zero realizable bad debt (via the health-bridge axioms below); the locked seller
// (only reachable re-entrantly) is scoped out.
rule realizableBadDebtCannotIncrease(env e, method f, calldataarg args, Midnight.Market market, address borrower) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    bytes32 id = summaryToId(market);

    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";
    require !liquidationLocked(id, borrower), "scope out the locked (re-entrant) seller case";

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d. axiomUpGeqDown(a, b, d), "axiom";
    require forall mathint a. forall mathint lif. forall mathint lltv. axiomLifLLTV(a, lif, lltv), "axiom";
    require forall uint256 lltv. forall uint256 cursor. lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "maxLif is at most 1/lltv";

    uint256 rbdBefore = realizableBadDebt(market, id, borrower);

    f(e, args);

    uint256 rbdAfter = realizableBadDebt(market, id, borrower);

    assert rbdAfter <= rbdBefore;
}

// liquidate realizes bad debt: it recomputes to zero and drops totalUnits by exactly the realized
// bad debt (src/Midnight.sol:673); the seize/repay block never touches totalUnits.
rule liquidateRealizesBadDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require market.collateralParams.length <= 2, "restrict collateralParams for loop tractability";
    require marketIsCreated(market), "market must be created (tickSpacing > 0)";
    require lossFactor(id) < max_uint128, "market lossFactor must not be saturated";
    require to_mathint(debt(id, borrower)) <= to_mathint(totalUnits(id)), "position debt bounded by totalUnits";

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require forall mathint a. forall mathint lif. forall mathint lltv. axiomLifLLTV(a, lif, lltv), "axiom";
    require forall mathint b. forall mathint d. axiomDownZero(b, d), "axiom";
    require forall uint256 lltv. forall uint256 cursor. lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "maxLif is at most 1/lltv";

    // Tight floor/ceil characterizations (proven in MulDiv.spec, matching LiquidationBoundedByLIF.spec).
    require forall mathint a. forall mathint b. forall mathint d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b, "axiom";
    require forall mathint a. forall mathint b. forall mathint d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b, "axiom";
    require forall mathint a. forall mathint b. forall mathint d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b, "axiom";
    require forall mathint a. forall mathint b. forall mathint d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b, "axiom";

    uint256 rbdBefore = realizableBadDebt(market, id, borrower);
    uint256 totalUnitsBefore = totalUnits(id);

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    uint256 rbdAfter = realizableBadDebt(market, id, borrower);

    assert rbdAfter == 0;
    assert rbdBefore > 0 => to_mathint(totalUnits(id)) == to_mathint(totalUnitsBefore) - to_mathint(rbdBefore);
}
