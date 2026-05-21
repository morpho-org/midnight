// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Havoc as callbackHavoc;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Callbacks can modify the whole state arbitrarily, and can only modify the ghost variables to allow
    // themselves as payer. Callbacks are checked to only be called by their corresponding function,
    // eg onLiquidate is only called by liquidate. onRatify and onSell cannot authorize a payer, so we
    // model them with a plain HAVOC_ALL.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => onCallBackSummary(calledContract, buyCallbackAllowed) expect(bytes32);
    function _.onLiquidate(bytes32, Midnight.Market, uint256, uint256, uint256, uint256, address, address, address, bytes) external => onCallBackSummary(calledContract, liquidateCallbackAllowed) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => onCallBackSummary(calledContract, repayCallbackAllowed) expect(bytes32);
    function _.onFlashLoan(address[], uint256[], address, bytes) external => onCallBackSummary(calledContract, flashLoanCallbackAllowed) expect(bytes32);

    // Checks every token pull against the current explicit-payer allowlist.
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(calledContract, src, dest, value) expect(bool);

    // Over-approximation for view functions: we are not looking at reverts and they cannot call callbacks.
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
}

persistent ghost address msgSender;

persistent ghost bool msgSenderAllowed;

persistent ghost address callback;

persistent ghost bool callbackAllowed;

persistent ghost bool buyCallbackAllowed;

persistent ghost bool liquidateCallbackAllowed;

persistent ghost bool repayCallbackAllowed;

persistent ghost bool flashLoanCallbackAllowed;

/// Tracks the maker address from a validated offer.
persistent ghost address maker;

persistent ghost bool makerAllowed;

persistent ghost bool badPullSeen;

function triggerHavocAll() {
    address dummy;
    env e;
    callbackHavoc.callHavoc(e, dummy);
}

function onCallBackSummary(address callbackAddress, bool allowedCallback) returns (bytes32) {
    assert allowedCallback;
    bytes32 result;
    triggerHavocAll();
    callback = callbackAddress;
    if (result == Utils.callbackSuccess()) {
        assert callbackAllowed == false;
        callbackAllowed = true;
    }
    return result;
}

function CVL_transferFrom(address token, address src, address dest, uint256 value) returns bool {
    bool success;
    if (!success) {
        revert();
    }

    triggerHavocAll();

    if (msgSenderAllowed && src == msgSender) {
        return true;
    }
    if (callbackAllowed && src == callback) {
        return true;
    }
    if (makerAllowed && src == maker) {
        return true;
    }

    badPullSeen = true;
    return true;
}

/// Proves that in `take`, the only addresses whose tokens can be pulled are:
/// 1. msg.sender (when !offer.buy and buyerCallback == 0),
/// 2. the buyerCallback that returned CALLBACK_SUCCESS,
/// 3. the offer maker (when offer.buy and buyerCallback == 0, i.e. maker is the buyer with no callback).
rule takeOnlyExplicitPayer(env e, Midnight.Offer offer, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, bytes ratifierData) {
    require e.msg.sender != currentContract, "only external calls";

    address buyerCallback = offer.buy ? offer.callback : takerCallback;

    msgSender = e.msg.sender;
    msgSenderAllowed = !offer.buy && buyerCallback == 0;
    callbackAllowed = false;
    maker = offer.maker;
    makerAllowed = offer.buy && buyerCallback == 0;

    buyCallbackAllowed = true;
    liquidateCallbackAllowed = false;
    repayCallbackAllowed = false;
    flashLoanCallbackAllowed = false;
    badPullSeen = false;

    take(e, offer, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData, ratifierData);

    assert !badPullSeen;
}

/// Proves that for every entry point other than `take`, tokens are only ever pulled from msg.sender
/// or from a callback that returned CALLBACK_SUCCESS.
rule otherEntryPointsOnlyPullFromCaller(method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:take(Midnight.Offer, uint256, address, address, address, bytes, bytes).selector } {
    require e.msg.sender != currentContract, "only external calls";

    msgSender = e.msg.sender;
    msgSenderAllowed = true;
    callbackAllowed = false;
    makerAllowed = false;

    buyCallbackAllowed = false;
    liquidateCallbackAllowed = f.selector == sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector;
    repayCallbackAllowed = f.selector == sig:repay(Midnight.Market, uint256, address, address, bytes).selector;
    flashLoanCallbackAllowed = f.selector == sig:flashLoan(address[], uint256[], address, bytes).selector;
    badPullSeen = false;

    f(e, args);

    assert !badPullSeen;
}
