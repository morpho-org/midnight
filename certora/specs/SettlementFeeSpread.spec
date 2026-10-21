// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

import "MulDivAxioms.spec";

using SettlementFeeUtils as SettlementFeeUtils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function settlementFee(bytes32, uint256) external returns (uint256) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function SettlementFeeUtils.defaultSettlementFee(address, address, uint256) external returns (uint256) envfree;

    // Summarize to return a non-deterministic value, but remember the last id returned.
    // The stored id is assumed to be the one in the interactions, which is sound since toId is called only once per rule.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Deterministic TickLib.tickToPrice summary to be able to reference the price in the rules.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);

    // Sound summary since toMarket is not used by the protocol.
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Over-approximate view functions for prover performance.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;

    // mulDiv is a deterministic ghost; the rules below assume only the MulDiv.spec facts they need, via MulDivAxioms.spec.
    // A nondeterministic overflow flag overapproximates reverts.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Dispatch the call to Midnight's getter, because the prover doesn't see that it only calls Midnight.
    function _.defaultSettlementFeeCbp(address, uint256) external => DISPATCHER(true);
}

persistent ghost bytes32 lastId;

function summaryToId(Midnight.Market market) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

persistent ghost summaryTickToPrice(uint256) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

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

// Facts from MulDiv.spec relating the assets computed by take (units times the buyer or seller price) to units times the fee.
// Commutativity turns the additivity axioms, stated in the first argument, into additivity in the price.
function requireSpreadAxioms(mathint units, mathint offerPrice, mathint fee) {
    require axiomMathMulDivDownCommutative(units, offerPrice, WAD()), "axiom";
    require axiomMathMulDivDownCommutative(units, offerPrice - fee, WAD()), "axiom";
    require axiomMathMulDivUpCommutative(units, offerPrice, WAD()), "axiom";
    require axiomMathMulDivUpCommutative(units, offerPrice + fee, WAD()), "axiom";

    // Buy offer: the buyer pays floor(units * offerPrice / WAD) and the seller receives floor(units * (offerPrice - fee) / WAD).
    require axiomMathMulDivAddDownDown(offerPrice - fee, fee, units, WAD()), "axiom";
    require axiomMathMulDivAddDownUp(offerPrice - fee, fee, units, WAD()), "axiom";

    // Sell offer: the buyer pays ceil(units * (offerPrice + fee) / WAD) and the seller receives ceil(units * offerPrice / WAD).
    require axiomMathMulDivAddUpDown(offerPrice, fee, units, WAD()), "axiom";
    require axiomMathMulDivAddUpUp(offerPrice, fee, units, WAD()), "axiom";

    // Bound floor and ceil of fee * units / WAD by the exact quotient.
    require axiomMathMulDivDownTightBound(fee, units, WAD()), "axiom";
    require axiomMathMulDivUpUpperBound(fee, units, WAD()), "axiom";
}

// Rounding always favors the maker:
//   1. buyer-maker pays at most floor(units * offerPrice / WAD).
//   2. seller-maker receives at least ceil(units * offerPrice / WAD).
// Note also that this rule ensures that the settlement fee is applied on the taker price, not the maker price.
rule makerFavorableRounding(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    uint256 offerPrice = summaryTickToPrice(offer.tick);
    require axiomMathMulDivDownRoundsDown(units, offerPrice, WAD()), "axiom";
    require axiomMathMulDivUpRoundsUp(units, offerPrice, WAD()), "axiom";

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    assert offer.buy => buyerAssets * WAD() <= units * offerPrice;
    assert !offer.buy => sellerAssets * WAD() >= units * offerPrice;
}

// The spread between what the buyer pays and what the seller receives is at least floor(units * fee / WAD) and at most ceil(units * fee / WAD).
// Assume that the market is created.
rule settlementFeeSpreadBounds(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    bytes32 id;
    require tickSpacing(id) > 0, "assume that the market is created";

    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;

    uint256 fee = settlementFee@withrevert(id, timeToMaturity);
    assert !lastReverted;
    requireSpreadAxioms(units, summaryTickToPrice(offer.tick), fee);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    assert buyerAssets - sellerAssets >= (units * fee) / WAD();
    assert buyerAssets - sellerAssets <= (units * fee + WAD() - 1) / WAD();
}

// Twin rule of settlementFeeSpreadBounds for a market that is not created yet at the start.
rule settlementFeeSpreadBoundsNotCreatedMarket(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    bytes32 id;
    require tickSpacing(id) == 0, "assume that the market is not yet created at the start";

    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;

    uint256 fee = SettlementFeeUtils.defaultSettlementFee(currentContract, offer.market.loanToken, timeToMaturity);
    requireSpreadAxioms(units, summaryTickToPrice(offer.tick), fee);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    assert buyerAssets - sellerAssets >= (units * fee) / WAD();
    assert buyerAssets - sellerAssets <= (units * fee + WAD() - 1) / WAD();
}
