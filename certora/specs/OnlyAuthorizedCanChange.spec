// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function ratified(address user, bytes32 root) external returns (bool) envfree;
    function authorizationNonce(address user) external returns (uint256) envfree;

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

/// AUTHORIZATION CHANGE RULES ///

/// No function (except setAuthorizedWithSig) can change isAuthorized(user, someone) unless the caller is the user or authorized by the user.
rule onlyAuthorizedCanChangeAuthorization(env e, method f, calldataarg data) filtered { f -> !f.isView && f.selector != sig:setAuthorizedWithSig(Midnight.Authorization memory, Midnight.Signature calldata).selector } {
    address user;
    address someone;

    require user != e.msg.sender;
    require !isAuthorized(user, e.msg.sender);

    bool authorizedBefore = isAuthorized(user, someone);

    f(e, data);

    bool authorizedAfter = isAuthorized(user, someone);

    assert authorizedAfter == authorizedBefore;
}

/// Only an authorized caller can change ratified(user, root).
rule onlyAuthorizedCanChangeRatified(env e, method f, calldataarg data, address user, bytes32 root) filtered { f -> !f.isView } {
    bool callerIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    bool before = ratified(user, root);
    f(e, data);
    assert callerIsAuthorized || ratified(user, root) == before;
}

/// Only setAuthorizedWithSig can change authorizationNonce.
rule nonceOnlyChangedBySetAuthorizedWithSig(env e, method f, calldataarg data, address user) filtered { f -> !f.isView && f.selector != sig:setAuthorizedWithSig(Midnight.Authorization memory, Midnight.Signature calldata).selector } {
    uint256 before = authorizationNonce(user);
    f(e, data);
    assert authorizationNonce(user) == before;
}

/// ACCESS CONTROL ///

/// Only the user or an authorized party can set ratification.
rule onlyUserOrAuthorizedCanRatify(env e, address onBehalf, bytes32 root, bool newIsRatified) {
    setRatified@withrevert(e, onBehalf, root, newIsRatified);
    assert !lastReverted => (onBehalf == e.msg.sender || isAuthorized(onBehalf, e.msg.sender));
}

/// take requires the caller to be the taker or authorized by the taker.
rule unauthorizedTakeFails(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert !lastReverted => e.msg.sender == taker || isAuthorized(taker, e.msg.sender);
}

/// withdrawCollateral requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedWithdrawCollateralFails(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    withdrawCollateral@withrevert(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// withdraw requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedWithdrawFails(env e, Midnight.Obligation obligation, uint256 obligationUnits, uint256 shares, address onBehalf, address receiver) {
    withdraw@withrevert(e, obligation, obligationUnits, shares, onBehalf, receiver);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// repay requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedRepayFails(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    repay@withrevert(e, obligation, obligationUnits, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// supplyCollateral requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedSupplyCollateralFails(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) {
    supplyCollateral@withrevert(e, obligation, collateralIndex, assets, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// setConsumed requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedSetConsumedFails(env e, bytes32 group, uint256 amount, address onBehalf) {
    setConsumed@withrevert(e, group, amount, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// shuffleSession requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedShuffleSessionFails(env e, address onBehalf) {
    shuffleSession@withrevert(e, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// ISOLATION ///

/// setIsAuthorized only changes the specified (onBehalf, authorized) pair.
rule setIsAuthorizedIsolation(env e, address onBehalf, address authorized, bool val, address otherUser, address otherAuthorized) {
    require otherUser != onBehalf || otherAuthorized != authorized;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setIsAuthorized(e, onBehalf, authorized, val);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}
