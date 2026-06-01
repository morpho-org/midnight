// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using TakeAmountsLibHarness as TakeAmountsLibHarness;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function settlementFee(bytes32, uint256) external returns (uint256) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;

    function TakeAmountsLibHarness.buyerAssetsToUnits(address, bytes32, Midnight.Offer, uint256) external returns (uint256);
    function TakeAmountsLibHarness.sellerAssetsToUnits(address, bytes32, Midnight.Offer, uint256) external returns (uint256);

    // Deterministic id: same Market => same id. Matches what take() and TakeAmountsLib observe (both reach IdLib.toId via Midnight.toId / Midnight.touchMarket).
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

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

persistent ghost summaryTickToPrice(uint256) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

/// MULDIV GHOST SUMMARIES (mirrors AccrualRounding.spec) ///

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDownM(0, b, d) == 0;
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint {
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivUpM(0, b, d) == 0;
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivDownM(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivUpM(a, b, d));
}

/// AXIOMS (each proved in MulDiv.spec against the real implementation) ///

/* proved in mulDivUpRoundsUp */
definition axiomUpLowerBound(mathint a, mathint b, mathint d) returns bool = 0 <= a && 0 <= b && 0 < d => summaryMulDivUpM(a, b, d) * d >= a * b;

/* proved in mulDivUpUpperBound */
definition axiomUpUpperBound(mathint a, mathint b, mathint d) returns bool = 0 <= a && 0 <= b && 0 < d => summaryMulDivUpM(a, b, d) * d <= a * b + d - 1;

/* proved in mulDivDownRoundsDown */
definition axiomDownUpperBound(mathint a, mathint b, mathint d) returns bool = 0 <= a && 0 <= b && 0 < d => summaryMulDivDownM(a, b, d) * d <= a * b;

/* proved in mulDivDownTightBound */
definition axiomDownTightBound(mathint a, mathint b, mathint d) returns bool = 0 <= a && 0 <= b && 0 < d => (summaryMulDivDownM(a, b, d) + 1) * d > a * b;

function requireMulDivAxioms() {
    require forall mathint a. forall mathint b. forall mathint d. axiomUpLowerBound(a, b, d), "axiomUpLowerBound";
    require forall mathint a. forall mathint b. forall mathint d. axiomUpUpperBound(a, b, d), "axiomUpUpperBound";
    require forall mathint a. forall mathint b. forall mathint d. axiomDownUpperBound(a, b, d), "axiomDownUpperBound";
    require forall mathint a. forall mathint b. forall mathint d. axiomDownTightBound(a, b, d), "axiomDownTightBound";
}

/// TAKE AMOUNTS LIB INVERTIBILITY ///

// Invertibility of TakeAmountsLib.buyerAssetsToUnits.
//
// If buyerAssetsToUnits(midnight, id, offer, T) returns u, then take(u, ...) produces buyerAssets == T.
rule buyerAssetsReachable(env e, Midnight.Offer offer, uint256 targetBuyerAssets, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, bytes ratifierData) {
    requireMulDivAxioms();

    bytes32 id = summaryToId(offer.market);
    require tickSpacing(id) > 0, "market is already created";

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
    requireMulDivAxioms();

    bytes32 id = summaryToId(offer.market);
    require tickSpacing(id) > 0, "market is already created";

    // Mirror the library's sellerPrice computation in CVL to express the WAD precondition.
    uint256 offerPrice = summaryTickToPrice(offer.tick);
    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;
    uint256 fee = settlementFee(id, timeToMaturity);
    require !offer.buy || fee <= offerPrice, "library reverts otherwise";
    uint256 sellerPrice = offer.buy ? assert_uint256(offerPrice - fee) : offerPrice;
    require sellerPrice <= WAD(), "invertibility requires sellerPrice <= WAD";

    uint256 units = TakeAmountsLibHarness.sellerAssetsToUnits(e, currentContract, id, offer, targetSellerAssets);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert sellerAssets == targetSellerAssets;
}
