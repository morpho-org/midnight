// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    // Verify the real multicall batching path instead of havocing it away.

    // Summarize internals/external calls irrelevant to token pull provenance.
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

    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes data) external with(env e) => onBuySummary(e, calledContract, data) expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes data) external with(env e) => onSellSummary(e, calledContract, data) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes data) external with(env e) => onVoidCallbackSummary(e, calledContract, data) expect void;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes data) external with(env e) => onVoidCallbackSummary(e, calledContract, data) expect void;
    function _.onFlashLoan(address, uint256, bytes data) external with(env e) => onVoidCallbackSummary(e, calledContract, data) expect void;

    // Track ERC20 debits precisely at the transferFrom boundary.
    function _.transfer(address dest, uint256 value) external with(env e) => CVL_transfer(calledContract, e.msg.sender, dest, value) expect(bool);
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(e, calledContract, src, dest, value) expect(bool);
}

ghost mapping(address => mapping(address => uint256)) tokenBalances;

ghost address topLevelCaller;

ghost address pendingSignedMaker;

ghost bool pendingSignedMakerEligible {
    init_state axiom !pendingSignedMakerEligible;
}

ghost uint256 pendingSignedMakerPullsRemaining {
    init_state axiom pendingSignedMakerPullsRemaining == 0;
}

ghost address pendingBuyerCallback;

ghost uint256 pendingBuyerCallbackPullsRemaining {
    init_state axiom pendingBuyerCallbackPullsRemaining == 0;
}

ghost uint256 reentrantCallbackDepth {
    init_state axiom reentrantCallbackDepth == 0;
}

ghost mapping(uint256 => address) reentrantCallerAtDepth;

function signerSummary() returns address {
    address result;
    pendingSignedMaker = result;
    pendingSignedMakerEligible = true;
    pendingSignedMakerPullsRemaining = 2;
    return result;
}

function reenterAs(env callbackEnv) {
    env nestedEnv;
    calldataarg nestedArgs;

    require nestedEnv.block.timestamp == callbackEnv.block.timestamp;
    require nestedEnv.block.number == callbackEnv.block.number;
    require nestedEnv.msg.value == callbackEnv.msg.value;

    reentrantCallbackDepth = assert_uint256(reentrantCallbackDepth + 1);
    reentrantCallerAtDepth[reentrantCallbackDepth] = nestedEnv.msg.sender;
    multicall(nestedEnv, nestedArgs);
    reentrantCallbackDepth = assert_uint256(reentrantCallbackDepth - 1);
}

function onBuySummary(env e, address callback, bytes data) returns (bytes32) {
    bytes32 result;

    pendingSignedMakerEligible = false;
    pendingSignedMakerPullsRemaining = 0;
    pendingBuyerCallbackPullsRemaining = 0;

    if (result == Utils.callbackSuccess()) {
        reenterAs(e);
    
        pendingSignedMakerEligible = false;
        pendingSignedMakerPullsRemaining = 0;
        pendingBuyerCallback = callback;
        pendingBuyerCallbackPullsRemaining = 2;
    }

    return result;
}

function onSellSummary(env e, address callback, bytes data) returns (bytes32) {
    bytes32 result;

    pendingSignedMakerEligible = false;
    pendingSignedMakerPullsRemaining = 0;
    pendingBuyerCallbackPullsRemaining = 0;

    if (result == Utils.callbackSuccess()) {
        reenterAs(e);
    
        pendingSignedMakerEligible = false;
        pendingSignedMakerPullsRemaining = 0;
        pendingBuyerCallbackPullsRemaining = 0;
    }

    return result;
}

function onVoidCallbackSummary(env e, address callback, bytes data) {
    pendingSignedMakerEligible = false;
    pendingSignedMakerPullsRemaining = 0;
    pendingBuyerCallbackPullsRemaining = 0;

    reenterAs(e);

    pendingSignedMakerEligible = false;
    pendingSignedMakerPullsRemaining = 0;
    pendingBuyerCallbackPullsRemaining = 0;
}

hook Sstore position[KEY bytes32 id][KEY address user].credit uint128 newVal (uint128 oldVal) {
    if (user == pendingSignedMaker && newVal < oldVal) {
        pendingSignedMakerEligible = false;
        pendingSignedMakerPullsRemaining = 0;
    }
}

hook Sstore position[KEY bytes32 id][KEY address user].debt uint128 newVal (uint128 oldVal) {
    if (user == pendingSignedMaker && newVal > oldVal) {
        pendingSignedMakerEligible = false;
        pendingSignedMakerPullsRemaining = 0;
    }
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

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    bool success;
    if (success) {
        bool inReentrantCallback = reentrantCallbackDepth > 0;
        bool fromCurrentCaller = inReentrantCallback ? src == reentrantCallerAtDepth[reentrantCallbackDepth] : src == topLevelCaller;
        bool fromBuyerCallback = src == pendingBuyerCallback && pendingBuyerCallbackPullsRemaining > 0;
        bool fromSignedMaker = src == pendingSignedMaker && pendingSignedMakerEligible && pendingSignedMakerPullsRemaining > 0;
    
        assert fromCurrentCaller || fromBuyerCallback || fromSignedMaker;
    
        if (fromBuyerCallback) {
            pendingBuyerCallbackPullsRemaining = assert_uint256(pendingBuyerCallbackPullsRemaining - 1);
        }
        if (fromSignedMaker) {
            pendingSignedMakerPullsRemaining = assert_uint256(pendingSignedMakerPullsRemaining - 1);
        }
    
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

rule onlyExplicitPayerCanLoseTokens(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        || f.selector == sig:repay(Midnight.Obligation, uint256, address, bytes).selector
        || f.selector == sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        || f.selector == sig:flashLoan(address, uint256, address, bytes).selector
        || f.selector == sig:multicall(bytes[]).selector
} {
    require e.msg.sender != currentContract, "only external calls";

    topLevelCaller = e.msg.sender;
    reentrantCallbackDepth = 0;
    pendingSignedMakerEligible = false;
    pendingSignedMakerPullsRemaining = 0;
    pendingBuyerCallbackPullsRemaining = 0;

    f(e, args);
    assert true;
}
