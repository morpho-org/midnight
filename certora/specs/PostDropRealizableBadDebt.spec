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
import "MulDivAxioms.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Per-callee price is modelled by a ghost mappings from oracle to price.
    // The change of the price in a rule can then be modelled by updating the mapping.
    function _.price() external => summaryPrice[calledContract] expect(uint256);

    // toId only keys position[id]/marketState[id], so the proof just needs a deterministic injective
    // market -> id map. Its abi.encodePacked is not injective in CVL, so we summarize by
    // keccak256(abi.encode(market)) (hashMarket), which is injective and applied uniformly.
    // storeInCode's returned address and code write never feed the accounting or price the rule reads.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;

    // Abstract deterministic summaries for mathematical functions.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // All external calls are assumed non-reentrant / non-reverting: we reason about the function bodies for safety properties.
    function _.transfer(address, uint256) external => HAVOC_ECF;
    function _.transferFrom(address, address, uint256) external => HAVOC_ECF;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => HAVOC_ECF;
}

/// SUMMARIES / GHOSTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost mapping(address => uint256) summaryPrice;

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

/// RULES ///

// Realizable bad debt cannot increase from liquidating before a price drop.
// If price drop happens after a liquidate, the total bad debt is less than if the liquidate
// never happened.
rule postDropRbdLiquidateNonIncrease(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);
    require maxLif >= to_mathint(WAD()), "see maxLifIsAtLeastWad in ExactMath.spec";

    uint256 price;
    uint256 pDrop;
    require pDrop <= price, "the dropped price is less than the initial price";

    mathint seizedAssetsOut;

    if (repaidUnits == 0) {
        seizedAssetsOut = seizedAssets;
    } else {
        // This computes an upper bound of the seizedAssetsOut computed by liquidate() (using maxLif).
        // The proof reasons about the worst-case, the real case follows from this by the monotonicity axioms.
        seizedAssetsOut = ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price);
        require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomMathMulDivDownMonotoneA(a1, a2, b, d), "axiom";
        require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomMathMulDivDownMonotoneB(a, b1, b2, d), "axiom";
        require axiomMathMulDivInverseUpDown(repaidUnits, maxLif, WAD()), "axiom";
        require axiomMathMulDivInverseUpDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    }

    uint256 collateralBefore = collateral(id, borrower, collateralIndex);
    mathint collateralAfter = collateralBefore - seizedAssetsOut;

    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomMathMulDivDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomMathMulDivUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomMathMulDivUpMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomMathMulDivUpMonotoneD(a, b, d1, d2), "axiom";

    require axiomMathMulDivUpZeroA(pDrop, ORACLE_PRICE_SCALE()), "axiom";
    require axiomMathMulDivUpZeroA(WAD(), maxLif), "axiom";
    require axiomMathMulDivAddUpUp(collateralAfter, seizedAssetsOut, pDrop, ORACLE_PRICE_SCALE()), "axiom";
    require axiomMathMulDivAddUpUp(ghostMulDivUp(collateralAfter, pDrop, ORACLE_PRICE_SCALE()), ghostMulDivUp(seizedAssetsOut, pDrop, ORACLE_PRICE_SCALE()), WAD(), maxLif), "axiom";

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
