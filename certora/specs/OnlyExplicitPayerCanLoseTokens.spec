// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.callbackSuccess() external returns (bytes32) envfree;

    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onCallBackSummary(calledContract) expect(bytes32);
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => onCallBackSummary(calledContract) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => onCallBackSummary(calledContract) expect(bytes32);
    function _.onFlashLoan(address, uint256, bytes) external => onCallBackSummary(calledContract) expect(bytes32);

    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;

    function _.transfer(address dest, uint256 value) external with(env e) => CVL_transfer(calledContract, e.msg.sender, dest, value) expect(bool);
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(calledContract, src, dest, value) expect(bool);
}

ghost mapping(address => mapping(address => uint256)) tokenBalances;

ghost address topLevelCaller;

ghost bool topLevelCallerAllowed {
    init_state axiom !topLevelCallerAllowed;
}

ghost address allowedBuyerCallback;

ghost bool allowedBuyerCallbackActive {
    init_state axiom !allowedBuyerCallbackActive;
}

/// Tracks the maker address from a validated offer.
ghost address allowedMaker;

ghost bool allowedMakerActive {
    init_state axiom !allowedMakerActive;
}

ghost bool badPullSeen {
    init_state axiom !badPullSeen;
}

function onCallBackSummary(address callback) returns (bytes32) {
    require callback != 0, "address(0) has no code and cannot return CALLBACK_SUCCESS";
    bytes32 result;
    allowedBuyerCallback = callback;
    allowedBuyerCallbackActive = result == Utils.callbackSuccess();
    return result;
}

function CVL_transfer(address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    bool success;
    if (success) {
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

function CVL_transferFrom(address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    bool success;
    if (success) {
        bool fromTopLevelCaller = topLevelCallerAllowed && src == topLevelCaller;
        bool fromSuccessfulBuyerCallback = allowedBuyerCallbackActive && src == allowedBuyerCallback;
        bool fromMakerWithCallbackZero = allowedMakerActive && src == allowedMaker;
    
        if (!(fromTopLevelCaller || fromSuccessfulBuyerCallback || fromMakerWithCallbackZero)) {
            badPullSeen = true;
        }
    
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

/// Proves that in `take`, the only addresses whose tokens can be pulled are:
/// 1. msg.sender (when !offer.buy and buyerCallback == 0),
/// 2. the buyerCallback that returned CALLBACK_SUCCESS,
/// 3. the offer maker (when offer.buy and buyerCallback == 0, i.e. maker's offer was ratified).
rule takeOnlyExplicitPayer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require e.msg.sender != currentContract, "only external calls";

    address buyerCallback = offer.buy ? offer.callback : takerCallback;

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = !offer.buy && buyerCallback == 0;
    allowedBuyerCallback = buyerCallback;
    allowedBuyerCallbackActive = false;
    allowedMaker = offer.maker;
    allowedMakerActive = offer.buy && buyerCallback == 0;
    badPullSeen = false;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert !badPullSeen, "tokens pulled from someone other than msg.sender, successful buyerCallback, or ratified maker";
}

/// Proves that for every entry point other than `take`, tokens are only ever pulled from msg.sender
/// or from a callback that returned CALLBACK_SUCCESS.
rule otherEntryPointsOnlyPullFromCaller(method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    require e.msg.sender != currentContract, "only external calls";

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = true;
    allowedBuyerCallbackActive = false;
    allowedMakerActive = false;
    badPullSeen = false;

    f(e, args);

    assert !badPullSeen, "tokens pulled from someone other than msg.sender";
}
