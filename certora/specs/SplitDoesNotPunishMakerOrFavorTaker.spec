// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Same offer.tick across all take calls; CONSTANT ensures identical return value.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Merkle proof: irrelevant to asset computation, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // zeroFloorSub feeds into timeToMaturity (only used by tradingFee, already CONSTANT) and buyerCreditIncrease (affects position state, not return values). NONDET is safe for this property.
    function UtilsLib.zeroFloorSub(uint256, uint256) internal returns (uint256) => NONDET;

    // Skip obligation creation logic: irrelevant to asset computation, removes collateral loop.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    // Same obligation and timestamp across all take calls; CONSTANT ensures identical fee and removes piecewise interpolation.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Same (root, sig) on all take calls; CONSTANT ensures identical signer and removes ecrecover complexity.
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CONSTANT;

    // Read-only health check does not affect return values; removes oracle loop.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

/// GHOSTS ///

persistent ghost bytes32 ghostId;

/// SUMMARY FUNCTIONS ///

function CVL_toId() returns bytes32 {
    return ghostId;
}

/// Splitting an offer does not punish the maker or favor the taker on asset amounts.
/// When offer.buy (maker=buyer, taker=seller): Maker pays less or equal when split, taker receives less or equal when split.
/// When !offer.buy (maker=seller, taker=buyer): Maker receives more or equal when split, taker pays more or equal when split.
rule splitDoesNotPunishMakerOrFavorTaker(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    uint256 buyerAssetsA;
    uint256 sellerAssetsA;
    buyerAssetsA, sellerAssetsA, _ = take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    // Path 2: take B then C from the initial state.
    uint256 buyerAssetsB;
    uint256 sellerAssetsB;
    buyerAssetsB, sellerAssetsB, _ = take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof) at initState;

    uint256 buyerAssetsC;
    uint256 sellerAssetsC;
    buyerAssetsC, sellerAssetsC, _ = take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    // Maker is buyer: splitting should not make them pay more.
    assert offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) <= to_mathint(buyerAssetsA);

    // Taker is seller: splitting should not make them receive more.
    assert offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) <= to_mathint(sellerAssetsA);

    // Maker is seller: splitting should not make them receive less.
    assert !offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) >= to_mathint(sellerAssetsA);

    // Taker is buyer: splitting should not make them pay less.
    assert !offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) >= to_mathint(buyerAssetsA);
}
