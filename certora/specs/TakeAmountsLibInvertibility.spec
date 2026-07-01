// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;
using TakeAmountsLibHarness as TakeAmountsLibHarness;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function settlementFee(bytes32, uint256) external returns (uint256) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;

    function TakeAmountsLibHarness.buyerAssetsToUnits(address, bytes32, Midnight.Offer, uint256) external returns (uint256);
    function TakeAmountsLibHarness.sellerAssetsToUnits(address, bytes32, Midnight.Offer, uint256) external returns (uint256);

    // Deterministic toId function.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Deterministic price: the same tick yields the same price for both the library and take().
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);

    // Dispatch TakeAmountsLib's external call IMidnight(midnight).settlementFee(...) to currentContract,
    // so the value the library reads matches the value take() reads internally.
    function _.settlementFee(bytes32, uint256) external => DISPATCHER(true);

    // Axiomatic mulDiv summaries.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Assume no reentrancy: callbacks and transfers do not re-enter Midnight.
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

// tickToPrice maps every valid tick into [0, WAD] (proved in TickToPrice.spec: tickToPriceAtMostWad, with
// equality reached at MAX_TICK via tickToPriceIsOneAtMaxTick).
persistent ghost summaryTickToPrice(uint256) returns uint256 {
    axiom forall uint256 tick. summaryTickToPrice(tick) <= 10 ^ 18;
}

definition WAD() returns uint256 = 10 ^ 18;

/// MULDIV GHOST SUMMARIES (mirrors AccrualRounding.spec) ///

// MulDiv rounding axioms (each proved in MulDiv.spec); inlined on ghosts instead of requireMulDivAxioms().
persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint {
    // proved in mulDivUpRoundsUp
    axiom forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(0, b, d) == 0;

    // proved in mulDivDownRoundsDown
    axiom forall mathint a. forall mathint b. forall mathint d. 0 <= a && 0 <= b && 0 < d => ghostMulDivDown(a, b, d) * d <= a * b;

    // proved in mulDivDownTightBound
    axiom forall mathint a. forall mathint b. forall mathint d. 0 <= a && 0 <= b && 0 < d => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
}

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint {
    // proved in mulDivUpRoundsUp
    axiom forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(0, b, d) == 0;

    // proved in mulDivUpRoundsUp
    axiom forall mathint a. forall mathint b. forall mathint d. 0 <= a && 0 <= b && 0 < d => ghostMulDivUp(a, b, d) * d >= a * b;

    // proved in mulDivUpUpperBound
    axiom forall mathint a. forall mathint b. forall mathint d. 0 <= a && 0 <= b && 0 < d => ghostMulDivUp(a, b, d) * d <= a * b + d - 1;
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || a * b > max_uint256) {
        revert();
    }
    return assert_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || a * b > max_uint256) {
        revert();
    }
    return assert_uint256(ghostMulDivUp(a, b, d));
}

/// TAKE AMOUNTS LIB INVERTIBILITY ///

// Invertibility of TakeAmountsLib.buyerAssetsToUnits.
//
// If buyerAssetsToUnits(midnight, id, offer, T) returns u, then take(u, ...) produces buyerAssets == T.
rule buyerAssetsReachable(env e, Midnight.Offer offer, uint256 targetBuyerAssets, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, bytes ratifierData) {
    bytes32 id = summaryToId(offer.market);

    uint256 units = TakeAmountsLibHarness.buyerAssetsToUnits(e, currentContract, id, offer, targetBuyerAssets);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert buyerAssets == targetBuyerAssets;
}

// Invertibility of TakeAmountsLib.sellerAssetsToUnits.
//
// If sellerAssetsToUnits(midnight, id, offer, T) returns u, then take(u, ...) produces sellerAssets == T.
rule sellerAssetsReachable(env e, Midnight.Offer offer, uint256 targetSellerAssets, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, bytes ratifierData) {
    bytes32 id = summaryToId(offer.market);

    uint256 units = TakeAmountsLibHarness.sellerAssetsToUnits(e, currentContract, id, offer, targetSellerAssets);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert sellerAssets == targetSellerAssets;
}
