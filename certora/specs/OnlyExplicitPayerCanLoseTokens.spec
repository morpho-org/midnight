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
    // eg onLiquidate is only called by liquidate. onRatify and onSell cannot authorize a payer
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onBuySummary(calledContract) expect(bytes32);
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => onLiquidateSummary(calledContract) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => onRepaySummary(calledContract) expect(bytes32);
    function _.onFlashLoan(address[], uint256[], bytes) external => onFlashLoanSummary(calledContract) expect(bytes32);
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => genericExternalCallBytes32() expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => genericExternalCallBytes32() expect(bytes32);

    // Checks every token pull against the current explicit-payer allowlist.
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(calledContract, src, dest, value) expect(bool);

    // Models outbound token sends as arbitrary external effects while preserving prover ghosts.
    function _.transfer(address dest, uint256 value) external => genericExternalCallBool() expect(bool);

    // Oracle prices are irrelevant to payer provenance.
    function _.price() external => NONDET;

    // Over-approximation for view functions: we are not looking at reverts and they cannot call callbacks.
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
}

ghost address topLevelCaller;

ghost bool topLevelCallerAllowed;

ghost address allowedCallbackPayer;

ghost bool allowedCallbackPayerActive;

ghost bool allowBuyCallbackAsPayer;

ghost bool allowLiquidateCallback;

ghost bool allowRepayCallbackAsPayer;

ghost bool allowFlashLoanCallbackAsPayer;

/// Tracks the maker address from a validated offer.
ghost address allowedMaker;

ghost bool allowedMakerActive;

ghost bool badPullSeen;

function havocPreservingGhosts() {
    address savedTopLevelCaller = topLevelCaller;
    bool savedTopLevelCallerAllowed = topLevelCallerAllowed;
    address savedAllowedCallbackPayer = allowedCallbackPayer;
    bool savedAllowedCallbackPayerActive = allowedCallbackPayerActive;
    bool savedAllowBuyCallbackAsPayer = allowBuyCallbackAsPayer;
    bool savedallowLiquidateCallback = allowLiquidateCallback;
    bool savedAllowRepayCallbackAsPayer = allowRepayCallbackAsPayer;
    bool savedAllowFlashLoanCallbackAsPayer = allowFlashLoanCallbackAsPayer;
    address savedAllowedMaker = allowedMaker;
    bool savedAllowedMakerActive = allowedMakerActive;
    bool savedBadPullSeen = badPullSeen;

    address dummy;
    env e;
    callback.callHavoc(e, dummy);

    topLevelCaller = savedTopLevelCaller;
    topLevelCallerAllowed = savedTopLevelCallerAllowed;
    allowedCallbackPayer = savedAllowedCallbackPayer;
    allowedCallbackPayerActive = savedAllowedCallbackPayerActive;
    allowBuyCallbackAsPayer = savedAllowBuyCallbackAsPayer;
    allowLiquidateCallback = savedallowLiquidateCallback;
    allowRepayCallbackAsPayer = savedAllowRepayCallbackAsPayer;
    allowFlashLoanCallbackAsPayer = savedAllowFlashLoanCallbackAsPayer;
    allowedMaker = savedAllowedMaker;
    allowedMakerActive = savedAllowedMakerActive;
    badPullSeen = savedBadPullSeen;
}

function genericExternalCallBytes32() returns (bytes32) {
    bytes32 result;
    havocPreservingGhosts();
    return result;
}

function genericExternalCallBool() returns (bool) {
    bool success;
    havocPreservingGhosts();
    if (!success) {
        revert();
    }
    return true;
}

function onBuySummary(address callbackAddress) returns (bytes32) {
    assert allowBuyCallbackAsPayer;
    return onCallBackSummary(callbackAddress);
}

function onLiquidateSummary(address callbackAddress) returns (bytes32) {
    assert allowLiquidateCallback;
    return onCallBackSummary(callbackAddress);
}

function onRepaySummary(address callbackAddress) returns (bytes32) {
    assert allowRepayCallbackAsPayer;
    return onCallBackSummary(callbackAddress);
}

function onFlashLoanSummary(address callbackAddress) returns (bytes32) {
    assert allowFlashLoanCallbackAsPayer;
    return onCallBackSummary(callbackAddress);
}

function onCallBackSummary(address callbackAddress) returns (bytes32) {
    require callbackAddress != 0, "address(0) has no code and cannot return CALLBACK_SUCCESS";
    bytes32 result;
    havocPreservingGhosts();
    allowedCallbackPayer = callbackAddress;
    allowedCallbackPayerActive = result == Utils.callbackSuccess();
    return result;
}

function CVL_transferFrom(address token, address src, address dest, uint256 value) returns bool {
    bool success;
    if (!success) {
        revert();
    }

    havocPreservingGhosts();  
   
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
