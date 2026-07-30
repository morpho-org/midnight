// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Property: liquidating ahead of an oracle price drop cannot worsen the post-drop realizable bad debt.
//
// Concretely:  In the reference scenario there is no liquidation just a price drop and the
// bad debt is measured at the dropped price pDrop.
// In the second scenario there was a liquidate at some price >= pDrop before the price drop.
// The total bad debt in the second scenario (the bad debt before measured at initial price plus
// the additional bad debt after liquidating measured a the dropped price) must not exceed the
// bad debt in the reference scenario without a liquidation.
//
// This shows that timely liquidations before a price drop are never disadvantageous to the creditors.

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
definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);

// Monotone in the second argument (proven in MulDiv.spec as mulDivMonotoneB).
definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);

// Monotone in the first argument (proven in MulDiv.spec as mulDivMonotoneA).
definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

// Monotone in the second argument (proven in MulDiv.spec as mulDivMonotoneB).
definition axiomUpMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivUp(a, b1, d) <= ghostMulDivUp(a, b2, d);

// Monotone in the third argument (proven in MulDiv.spec as mulDivMonotoneD).
definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => ghostMulDivUp(a, b, d2) <= ghostMulDivUp(a, b, d1);

// Zero collateral values to zero (proven in MulDiv.spec as mulDivZero).
definition axiomUpZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivUp(0, b, d) == 0;

// proven in MulDiv.spec as mulDivAddUpUp:
//   mulDivUp(a1 + a2, b, d) <= mulDivUp(a1, b, d) + mulDivUp(a2, b, d).
definition axiomAddUpUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => ghostMulDivUp(a1 + a2, b, d) <= ghostMulDivUp(a1, b, d) + ghostMulDivUp(a2, b, d);

// proven in MulDiv.spec as mulDivAddUpUp:
//   mulDivUp(mulDivDown(a,b,d),d,b) <= a
definition axiomInverseUpDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a;

/// RULES ///

// Realizable bad debt cannot increase from liquidating before a price drop.
// If price drop happens after a liquidate, the total bad debt is less than if the liquidate
// never happened.
rule postDropRbdLiquidateNonIncrease(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "maxLif at least 1x (market-creation invariant)";

    uint256 price = summaryPrice[market.collateralParams[collateralIndex].oracle];
    uint256 pDrop;
    require pDrop <= price, "the dropped price is less than the initial price";

    mathint seizedAssetsOut;

    if (repaidUnits == 0) {
        seizedAssetsOut = seizedAssets;
    } else {
        seizedAssetsOut = ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price);
        require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
        require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
        require axiomInverseUpDown(repaidUnits, maxLif, WAD()), "axiom";
        require axiomInverseUpDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    }

    uint256 collateralBefore = collateral(id, borrower, collateralIndex);
    mathint collateralAfter = collateralBefore - seizedAssetsOut;

    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomUpMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";

    require axiomUpZero(pDrop, ORACLE_PRICE_SCALE()), "axiom";
    require axiomUpZero(WAD(), maxLif), "axiom";
    require axiomAddUpUp(collateralAfter, seizedAssetsOut, pDrop, ORACLE_PRICE_SCALE()), "axiom";
    require axiomAddUpUp(ghostMulDivUp(collateralAfter, pDrop, ORACLE_PRICE_SCALE()), ghostMulDivUp(seizedAssetsOut, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif), "axiom";

    // scenario 1: price drops, then realize bad debt
    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint badDebt1 = realizableBadDebt(market, id, borrower);

    // scenario 2: liquidate at initial (higher) price
    // then price drop, realize remaining debt.
    summaryPrice[market.collateralParams[collateralIndex].oracle] = price;

    mathint badDebt2a = realizableBadDebt(market, id, borrower);
    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    summaryPrice[market.collateralParams[collateralIndex].oracle] = pDrop;
    mathint badDebt2b = realizableBadDebt(market, id, borrower);

    // liquidating before the price drop (scenario 2) will cause less total bad debt than scenario 1.
    assert badDebt2a + badDebt2b <= badDebt1;
}
