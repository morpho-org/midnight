// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Havoc as callback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Helper used only to force a full storage havoc inside summaries.
    function _.havocAll() external => HAVOC_ALL;

    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Callbacks can modify the whole state arbitrarily, and can only modify the ghost variables to allow
    // themselves as payer. Callbacks are checked to only be called by their corresponding function,
    // eg onLiquidate is only called by liquidate. onRatify and onSell cannot authorize a payer, so we
    // model them with a plain HAVOC_ALL.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onCallBackSummary(calledContract, allowBuyCallbackAsPayer) expect(bytes32);
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => onCallBackSummary(calledContract, allowLiquidateCallback) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => onCallBackSummary(calledContract, allowRepayCallbackAsPayer) expect(bytes32);
    function _.onFlashLoan(address[], uint256[], bytes) external => onCallBackSummary(calledContract, allowFlashLoanCallbackAsPayer) expect(bytes32);

    // Checks every token pull against the current explicit-payer allowlist.
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(calledContract, src, dest, value) expect(bool);

    function _.onRatify(Midnight.Offer, bytes32, bytes) external => HAVOC_ALL;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => HAVOC_ALL;

    function _._() external => HAVOC_ALL ALL;
    // Over-approximation for view functions: we are not looking at reverts and they cannot call callbacks.
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
}

persistent ghost address topLevelCaller;

persistent ghost bool topLevelCallerAllowed;

persistent ghost address allowedCallbackPayer;

persistent ghost bool allowedCallbackPayerActive;

persistent ghost bool allowBuyCallbackAsPayer;

persistent ghost bool allowLiquidateCallback;

persistent ghost bool allowRepayCallback;

persistent ghost bool allowFlashLoanCallback;

/// Tracks the maker address from a validated offer.
persistent ghost address allowedMaker;

persistent ghost bool allowedMakerActive;

persistent ghost bool badPullSeen;

function triggerHavocAll() {
    address dummy;
    env e;
    callback.callHavoc(e, dummy);
}

function onCallBackSummary(address callbackAddress, bool allowedCallback) returns (bytes32) {
    assert allowedCallback;
    require callbackAddress != 0, "address(0) has no code and cannot return CALLBACK_SUCCESS";
    bytes32 result;
    triggerHavocAll();
    allowedCallbackPayer = callbackAddress;
    allowedCallbackPayerActive = result == Utils.callbackSuccess();
    return result;
}

function CVL_transferFrom(address token, address src, address dest, uint256 value) returns bool {
    bool success;
    if (!success) {
        revert();
    }

    triggerHavocAll();

    if (topLevelCallerAllowed && src == topLevelCaller) {
        return true;
    }
    if (allowedCallbackPayerActive && src == allowedCallbackPayer) {
        return true;
    }
    if (allowedMakerActive && src == allowedMaker) {
        return true;
    }

    badPullSeen = true;
    return true;
}

/// Proves that in `take`, the only addresses whose tokens can be pulled are:
/// 1. msg.sender (when !offer.buy and buyerCallback == 0),
/// 2. the buyerCallback that returned CALLBACK_SUCCESS,
/// 3. the offer maker (when offer.buy and buyerCallback == 0, i.e. maker is the buyer with no callback).
rule takeOnlyExplicitPayer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require e.msg.sender != currentContract, "only external calls";

    address buyerCallback = offer.buy ? offer.callback : takerCallback;

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = !offer.buy && buyerCallback == 0;
    allowedCallbackPayerActive = false;
    allowBuyCallbackAsPayer = true;
    allowLiquidateCallback = false;
    allowRepayCallbackAsPayer = false;
    allowFlashLoanCallbackAsPayer = false;
    allowedMaker = offer.maker;
    allowedMakerActive = offer.buy && buyerCallback == 0;
    badPullSeen = false;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert !badPullSeen;
}

/// Proves that for every entry point other than `take`, tokens are only ever pulled from msg.sender
/// or from a callback that returned CALLBACK_SUCCESS.
rule otherEntryPointsOnlyPullFromCaller(method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    require e.msg.sender != currentContract, "only external calls";

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = true;
    allowedCallbackPayerActive = false;
    allowBuyCallbackAsPayer = false;
    allowLiquidateCallback = f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector;
    allowRepayCallbackAsPayer = f.selector == sig:repay(Midnight.Obligation, uint256, address, address, bytes).selector;
    allowFlashLoanCallbackAsPayer = f.selector == sig:flashLoan(address[], uint256[], address, bytes).selector;
    allowedMakerActive = false;
    badPullSeen = false;

    f(e, args);

    assert !badPullSeen;
}
