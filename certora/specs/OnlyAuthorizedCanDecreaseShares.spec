// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function sharesOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => NONDET;
}

/// An unauthorized caller cannot decrease a user's shares except via take.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant share decreases are not covered.
rule onlyAuthorizedCanDecreaseSharesExceptTake(env e, method f, bytes32 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);

    require user != e.msg.sender;
    require !isAuthorized(user, e.msg.sender);

    calldataarg args;
    f(e, args);

    assert sharesOf(id, user) >= sharesBefore || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector;
}

/// In take, the caller must be authorized by the taker and only the seller's shares can decrease.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and decrease a different user's shares.
rule takeOnlyAuthorizedSellerSharesDecrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address seller = offer.buy ? taker : offer.maker;
    address buyer = offer.buy ? offer.maker : taker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    bool reverted = lastReverted;
    uint256 sharesAfter = sharesOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => sharesAfter <= sharesBefore;
    assert user == buyer => sharesAfter >= sharesBefore;
    assert user != buyer && user != seller => sharesAfter == sharesBefore;
}
