// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Deterministic TickLib.tickToPrice summary to be able to reference the price in the rules.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);

    // Deterministic tradingFee summary to be able to reference the fee in the rules. Rules reconstruct the fee as summaryTradingFee(id, timeToMaturity).
    function tradingFee(bytes32 id, uint256 timeToMaturity) internal returns (uint256) => summaryTradingFee(id, timeToMaturity);

    // Sound summary since toObligation is not used by the protocol.
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    // Over-approximate view functions for prover performance.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

persistent ghost summaryTickToPrice(uint256) returns uint256;

persistent ghost summaryTradingFee(bytes32, uint256) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

// Rounding always favors the maker:
//   1. buyer-maker pays at most floor(units * offerPrice / WAD).
//   2. seller-maker receives at least ceil(units * offerPrice / WAD).
rule makerFavorableRounding(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    uint256 offerPrice = summaryTickToPrice(offer.tick);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets, _ = take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert offer.buy => buyerAssets * WAD() <= units * offerPrice;
    assert !offer.buy => sellerAssets * WAD() >= units * offerPrice;
}

// The trading fee cannot be bypassed: the spread between what the buyer pays and what
// the seller receives is at least floor(units * fee / WAD) and at most ceil(units * fee / WAD).
rule tradingFeeIsNotBypassed(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    uint256 timeToMaturity = e.block.timestamp <= offer.obligation.maturity ? assert_uint256(offer.obligation.maturity - e.block.timestamp) : 0;

    bytes32 id = summaryToId(offer.obligation);
    uint256 fee = summaryTradingFee(id, timeToMaturity);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets, _ = take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert buyerAssets - sellerAssets >= (units * fee) / WAD();
    assert buyerAssets - sellerAssets <= (units * fee + WAD() - 1) / WAD();
}

// Taking zero units must produce zero assets on both sides.
rule zeroUnitsTakeResultsInZeroAssets(env e, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets, _ = take(e, 0, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert buyerAssets == 0;
    assert sellerAssets == 0;
}
