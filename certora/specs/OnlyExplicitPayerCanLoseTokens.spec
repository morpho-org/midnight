// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    // This spec intentionally checks direct top-level payer selection only.
    // Callback-driven reentrancy and multicall batching are out of scope here.
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summaries for internals/external calls irrelevant to top-level payer selection.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function _.price() external => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;

    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => signerSummary();
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Deliberately no reentrancy modeling in this simplified spec.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onBuySummary(calledContract) expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    // Track token sends separately from token pulls.
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

ghost address allowedSignedMaker;

ghost bool allowedSignedMakerActive {
    init_state axiom !allowedSignedMakerActive;
}

ghost address expectedSigner;

ghost bool badPullSeen {
    init_state axiom !badPullSeen;
}

function signerSummary() returns address {
    return expectedSigner;
}

function onBuySummary(address callback) returns (bytes32) {
    bytes32 result;
    allowedBuyerCallback = callback;
    allowedBuyerCallbackActive = callback != 0 && result == Utils.callbackSuccess();
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
        bool fromSignedMakerWithCallbackZero = allowedSignedMakerActive && src == allowedSignedMaker;
    
        if (!(fromTopLevelCaller || fromSuccessfulBuyerCallback || fromSignedMakerWithCallbackZero)) {
            badPullSeen = true;
        }
    
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

rule takeOnlyExplicitPayer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require e.msg.sender != currentContract, "only external calls";

    address buyerCallback = offer.buy ? offer.callback : takerCallback;

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = !offer.buy && buyerCallback == 0;
    allowedBuyerCallback = buyerCallback;
    allowedBuyerCallbackActive = false;
    allowedSignedMaker = offer.maker;
    allowedSignedMakerActive = offer.buy && buyerCallback == 0;
    expectedSigner = offer.maker;
    badPullSeen = false;

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    assert !badPullSeen;
}

rule otherEntryPointsOnlyPullFromCaller(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:repay(Midnight.Obligation, uint256, address, bytes).selector
        || f.selector == sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        || f.selector == sig:flashLoan(address, uint256, address, bytes).selector
} {
    require e.msg.sender != currentContract, "only external calls";

    topLevelCaller = e.msg.sender;
    topLevelCallerAllowed = true;
    allowedBuyerCallbackActive = false;
    allowedSignedMakerActive = false;
    badPullSeen = false;

    f(e, args);

    assert !badPullSeen;
}
