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

ghost address signedMakerCandidate;

ghost bool signedMakerCandidateEligible {
    init_state axiom !signedMakerCandidateEligible;
}

ghost address successfulBuyerCallback;

ghost bool successfulBuyerCallbackActive {
    init_state axiom !successfulBuyerCallbackActive;
}

function signerSummary() returns address {
    address result;
    signedMakerCandidate = result;
    signedMakerCandidateEligible = true;
    return result;
}

function onBuySummary(address callback) returns (bytes32) {
    bytes32 result;

    signedMakerCandidateEligible = false;
    successfulBuyerCallback = callback;
    successfulBuyerCallbackActive = result == Utils.callbackSuccess();

    return result;
}

// In take, the maker is only the fallback payer on the buy path with zero buyer callback.
// The maker is the seller on the sell path, so a credit decrease or debt increase disables
// the signed-maker payer exemption before transferFrom executes.
hook Sstore position[KEY bytes32 id][KEY address user].credit uint128 newVal (uint128 oldVal) {
    if (user == signedMakerCandidate && newVal < oldVal) {
        signedMakerCandidateEligible = false;
    }
}

hook Sstore position[KEY bytes32 id][KEY address user].debt uint128 newVal (uint128 oldVal) {
    if (user == signedMakerCandidate && newVal > oldVal) {
        signedMakerCandidateEligible = false;
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

function CVL_transferFrom(address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    bool success;
    if (success) {
        bool fromTopLevelCaller = src == topLevelCaller;
        bool fromSuccessfulBuyerCallback = successfulBuyerCallbackActive && src == successfulBuyerCallback;
        bool fromSignedMakerWithCallbackZero = signedMakerCandidateEligible && src == signedMakerCandidate;
    
        assert fromTopLevelCaller || fromSuccessfulBuyerCallback || fromSignedMakerWithCallbackZero;
    
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
} {
    require e.msg.sender != currentContract, "only external calls";

    topLevelCaller = e.msg.sender;
    signedMakerCandidateEligible = false;
    successfulBuyerCallbackActive = false;

    f(e, args);
    assert true;
}
