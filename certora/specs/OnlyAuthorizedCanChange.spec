// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function ratified(address user, bytes32 root) external returns (bool) envfree;
    function authorizationNonce(address user) external returns (uint256) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Summarize complex internals irrelevant to credit and debt tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Assume no reentrancy: callbacks do not re-enter Midnight.
    function _.onBuy(Midnight.Offer, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Offer, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

function CVL_signer() returns address {
    address result;
    signed[result] = true;
    return result;
}

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via take, liquidate, and slash.
/// take verified separately
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptTakeLiquidateAndSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || signed[user];
}

/// COLLATERAL CHANGE RULES ///

/// An unauthorized caller cannot change a user's collateral except via liquidate.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeCollateralExceptLiquidate(env e, method f, calldataarg args, bytes32 id, address user, uint256 collateralIndex) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 collateralBefore = collateralOf(id, user, collateralIndex);
    f(e, args);
    uint256 collateralAfter = collateralOf(id, user, collateralIndex);

    assert collateralAfter == collateralBefore || userIsAuthorized;
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
rule unauthorizedTakeFails(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert !lastReverted => e.msg.sender == taker || isAuthorized(taker, e.msg.sender);
}

/// withdrawCollateral requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedWithdrawCollateralFails(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    withdrawCollateral@withrevert(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// withdraw requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedWithdrawFails(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) {
    withdraw@withrevert(e, obligation, units, onBehalf, receiver);
    assert !lastReverted => e.msg.sender == onBehalf || isAuthorized(onBehalf, e.msg.sender);
}

/// repay requires the caller to be onBehalf or authorized by onBehalf.
rule unauthorizedRepayFails(env e, Midnight.Obligation obligation, uint256 units, address onBehalf) {
    repay@withrevert(e, obligation, units, onBehalf);
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
