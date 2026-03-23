// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function session(address user) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function ratified(address user, bytes32 root) external returns (bool) envfree;
    function authorizationNonce(address user) external returns (uint256) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Summarize oracle calls.
    function _.price() external => NONDET;

    // Summarize complex internal functions irrelevant to authorization checks.
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Summarize TickLib functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summarize UtilsLib functions.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    function _.onBuy(Midnight.Offer, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Offer, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

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

/// An unauthorized caller cannot change a user's credit and debt except via take, liquidate, and updatePosition.
/// take verified separately
/// PASSIVE_FEE_RECIPIENT's credit can increase via fee accrual without authorization.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptTakeLiquidateAndUpdatePosition(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:updatePosition(Midnight.Obligation, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool isPassiveFeeRecipient = user == Utils.passiveFeeRecipient();

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || signed[user] || isPassiveFeeRecipient;
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

/// CONSUMED CHANGE RULES ///

/// An unauthorized or unsigned caller cannot change a user's consumed except via take.
/// take verified separately (takeRequiresMakerConsent proves maker consent; take updates consumed[maker][group]).
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant consumed changes are not covered.
rule onlyAuthorizedCanChangeConsumedExceptTake(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 consumedBefore = consumed(user, group);
    f(e, args);
    uint256 consumedAfter = consumed(user, group);

    assert consumedAfter == consumedBefore || userIsAuthorized || signed[user];
}

/// SESSION CHANGE RULES ///

/// An unauthorized caller cannot change a user's session.
rule onlyAuthorizedCanChangeSession(env e, method f, calldataarg args, address user) filtered { f -> !f.isView } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    bytes32 sessionBefore = session(user);
    f(e, args);
    bytes32 sessionAfter = session(user);

    assert sessionAfter == sessionBefore || userIsAuthorized;
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

/// ISOLATION ///

/// setAuthorizedWithSig only changes isAuthorized for the (authorizer, authorizee) in the authorization struct.
rule setAuthorizedWithSigIsolation(env e, Midnight.Authorization authorization, Midnight.Signature signature, address otherUser, address otherAuthorized) {
    require otherUser != authorization.authorizer || otherAuthorized != authorization.authorizee;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setAuthorizedWithSig(e, authorization, signature);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}

/// setRatified only changes the specified (onBehalf, root) pair.
rule setRatifiedIsolation(env e, address onBehalf, bytes32 root, bool val, address otherUser, bytes32 otherRoot) {
    require otherUser != onBehalf || otherRoot != root;

    bool before = ratified(otherUser, otherRoot);
    setRatified(e, onBehalf, root, val);
    assert ratified(otherUser, otherRoot) == before;
}
