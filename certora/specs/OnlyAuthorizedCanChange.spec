// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function toId(Midnight.Market market) external returns (bytes32) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Summarize complex internal functions irrelevant to authorization checks.
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;

    // Summarize TickLib functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summarize UtilsLib functions.
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.isRatified(Midnight.Offer offer, bytes) external => CVL_isRatified(offer) expect(bytes32);
    function _.onFlashLoan(address[], uint256[], bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

ghost mapping(address => bool) makerRatified {
    init_state axiom forall address a. makerRatified[a] == false;
}

function CVL_isRatified(Midnight.Offer offer) returns bytes32 {
    bytes32 result;
    makerRatified[offer.maker] = true;
    return result;
}

definition noAccrual(env e, bytes32 id, address borrower) returns bool = currentContract.position[id][borrower].pendingFee == 0 || e.block.timestamp == currentContract.position[id][borrower].lastAccrual;

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via liquidate and updatePosition.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptLiquidateAndUpdatePosition(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector && f.selector != sig:updatePosition(Midnight.Market, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || makerRatified[user];
}

/// COLLATERAL CHANGE RULES ///

/// An unauthorized caller cannot change a user's collateral except via liquidate.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeCollateralExceptLiquidate(env e, method f, calldataarg args, bytes32 id, address user, uint256 collateralIndex) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 collateralBefore = collateral(id, user, collateralIndex);
    f(e, args);
    uint256 collateralAfter = collateral(id, user, collateralIndex);

    assert collateralAfter == collateralBefore || userIsAuthorized;
}

/// CONSUMED CHANGE RULES ///

/// An unauthorized caller cannot change a user's consumed except via take.
/// For take, unauthorizedTakeFails, takeRequiresMakerConsent, and takeOnlyAuthorizedCanChangeDebt show that take can only change this consumed: consumed[offer.maker][offer.group], only with the right authorizations.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant consumed changes are not covered.
rule onlyAuthorizedCanChangeConsumedExceptTake(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 consumedBefore = consumed(user, group);
    f(e, args);
    uint256 consumedAfter = consumed(user, group);

    assert consumedAfter == consumedBefore || userIsAuthorized;
}

/// AUTHORIZATION CHANGE RULES ///

/// An unauthorized caller cannot change a user's isAuthorized mapping.
rule onlyAuthorizedCanChangeIsAuthorized(env e, method f, calldataarg args, address authorizer, address authorized) filtered { f -> !f.isView } {
    bool authorizerIsAuthorized = authorizer == e.msg.sender || isAuthorized(authorizer, e.msg.sender);

    bool isAuthorizedBefore = isAuthorized(authorizer, authorized);
    f(e, args);
    bool isAuthorizedAfter = isAuthorized(authorizer, authorized);

    assert isAuthorizedAfter == isAuthorizedBefore || authorizerIsAuthorized;
}

/// ACCESS CONTROL ///

/// take requires the caller to be the taker or authorized by the taker
rule unauthorizedTakeFails(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    bool senderAuthorized = isAuthorized(taker, e.msg.sender);
    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);

    assert e.msg.sender == taker || senderAuthorized;
}

/// ISOLATION ///

/// setIsAuthorized only changes the specified (onBehalf, authorized) pair.
rule setIsAuthorizedIsolation(env e, address onBehalf, address authorized, bool val, address otherUser, address otherAuthorized) {
    require otherUser != onBehalf || otherAuthorized != authorized;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setIsAuthorized(e, onBehalf, authorized, val);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}
