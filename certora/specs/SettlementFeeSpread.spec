// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using SettlementFeeUtils as SettlementFeeUtils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function settlementFee(bytes32, uint256) external returns (uint256) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function SettlementFeeUtils.defaultSettlementFee(address, address, uint256) external returns (uint256) envfree;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Deterministic TickLib.tickToPrice summary to be able to reference the price in the rules.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);

    // Sound summary since toMarket is not used by the protocol.
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Over-approximate view functions for prover performance.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;

    // SettlementFeeUtils reads the defaults through the IMidnight interface; dispatch the call to Midnight's getter so
    // it reads currentContract's storage instead of being havoc'd to an arbitrary value.
    function _.defaultSettlementFeeCbp(address, uint256) external => DISPATCHER(true);

    // The settlement fee spread only depends on buyerAssets/sellerAssets, which take computes before touching any
    // position state or making external calls. Summarize the rest of take's body away to cut the prover's work:
    // these summaries cannot affect the asserted values, but they remove position accounting, the touchMarket maxLif
    // loop, and the havoc-all external callbacks/transfers from the verification condition.
    function _updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

persistent ghost summaryTickToPrice(uint256) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

// Rounding always favors the maker:
//   1. buyer-maker pays at most floor(units * offerPrice / WAD).
//   2. seller-maker receives at least ceil(units * offerPrice / WAD).
// Note also that this rule ensures that the settlement fee is applied on the taker price, not the maker price.
rule makerFavorableRounding(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    uint256 offerPrice = summaryTickToPrice(offer.tick);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    assert offer.buy => buyerAssets * WAD() <= units * offerPrice;
    assert !offer.buy => sellerAssets * WAD() >= units * offerPrice;
}

// The spread between what the buyer pays and what the seller receives is at least floor(units * fee / WAD) and at most ceil(units * fee / WAD).
rule settlementFeeSpreadBounds(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;
    bytes32 id = summaryToId(offer.market);

    // take calls touchMarket see rule takeCallsTouchMarket.
    // Thus calling settlementFee (in particular checking if the market is touched) doesn't prune meaningful take paths.
    uint256 fee = settlementFee(id, timeToMaturity);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    assert buyerAssets - sellerAssets >= (units * fee) / WAD();
    assert buyerAssets - sellerAssets <= (units * fee + WAD() - 1) / WAD();
}

// Twin of settlementFeeSpreadBounds for a market that is not created yet at the start.
// take calls touchMarket, which creates the market by copying the loan token's default settlement fee cbps into the
// market state. The applied fee is then derived from those defaults, computed exactly as in settlementFee.
rule settlementFeeSpreadBoundsNotCreatedMarket(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    bytes32 id = summaryToId(offer.market);
    require tickSpacing(id) == 0;

    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;

    // The fee is derived from the loan token's default settlement fee cbps, which touchMarket copies into the market state.
    uint256 fee = SettlementFeeUtils.defaultSettlementFee(currentContract, offer.market.loanToken, timeToMaturity);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    assert buyerAssets - sellerAssets >= (units * fee) / WAD();
    assert buyerAssets - sellerAssets <= (units * fee + WAD() - 1) / WAD();
}
