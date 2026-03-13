// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => NONDET;
}

/// A single take cannot change both a user's shares and debt.
rule takeCannotChangeBothSharesAndDebt(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 sharesAfter = sharesOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert sharesAfter == sharesBefore || debtAfter == debtBefore;
}

/// SHARES CHANGE RULES ///

/// An unauthorized caller cannot change a user's shares except via take.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant share decreases are not covered.
rule onlyAuthorizedCanChangeSharesExceptTake(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);
    f(e, args);
    uint256 sharesAfter = sharesOf(id, user);

    assert userIsAuthorized || sharesAfter == sharesBefore;
}

/// In take, the caller must be authorized by the taker and only the seller's shares can decrease.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and decrease a different user's shares.
rule takeOnlyAuthorizedSellerSharesDecrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address seller = offer.buy ? taker : offer.maker;
    address buyer = offer.buy ? offer.maker : taker;
    bool takerIsAuthorized = e.msg.sender == taker || isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 sharesAfter = sharesOf(id, user);

    assert takerIsAuthorized;
    assert user == seller => sharesAfter <= sharesBefore;
    assert user == buyer => sharesAfter >= sharesBefore;
    assert user != buyer && user != seller => sharesAfter == sharesBefore;
}

/// DEBT CHANGE RULES ///

/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant debt decreases are not covered.
rule onlyAuthorizedCanChangeDebtExceptTakeAndLiquidate(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 debtAfter = debtOf(id, user);

    assert userIsAuthorized || debtAfter == debtBefore;
}

/// In liquidate, users can have their debt decreased.
rule liquidateCanChangeDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    uint256 debtAfter = debtOf(id, user);

    assert user == borrower => debtAfter <= debtBefore;
    assert user != borrower => debtAfter == debtBefore;
}

/// In take, the caller must be authorized by the taker, and only the seller's debt can increase.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and increase a different user's debt.
rule takeOnlyAuthorizedCanChangeDebt(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerIsAuthorized = e.msg.sender == taker || isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 debtAfter = debtOf(id, user);

    assert takerIsAuthorized;
    assert user == buyer => debtAfter <= debtBefore;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}
