// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summarize internal functions that use opcodes causing HAVOC or are irrelevant to token pull provenance.
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
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => signerSummary();
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onBuySummary(calledContract) expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => onSellSummary(calledContract) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    // Assume ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing, no blacklisting, no transfer limits.
    function _.transfer(address dest, uint256 value) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, dest, value) expect(bool);
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(e, calledContract, src, dest, value) expect(bool);
}

ghost mapping(address => mapping(address => uint256)) tokenBalances;

ghost mapping(address => bool) signedOffer {
    init_state axiom forall address a. signedOffer[a] == false;
}

ghost mapping(address => bool) callbackReturnedSuccess {
    init_state axiom forall address a. callbackReturnedSuccess[a] == false;
}

ghost bool buyerCallbackCalled {
    init_state axiom !buyerCallbackCalled;
}

function signerSummary() returns address {
    address result;
    signedOffer[result] = true;
    return result;
}

function onBuySummary(address callback) returns (bytes32) {
    bytes32 result;
    buyerCallbackCalled = true;
    callbackReturnedSuccess[callback] = result == Utils.callbackSuccess();
    return result;
}

function onSellSummary(address callback) returns (bytes32) {
    bytes32 result;
    callbackReturnedSuccess[callback] = result == Utils.callbackSuccess();
    return result;
}

definition signedOfferWithCallbackZero(address user) returns bool = signedOffer[user] && !buyerCallbackCalled;

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
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

rule onlyExplicitPayerCanLoseTokens(method f, env e, calldataarg args, address token, address user)
filtered {
    f -> f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        || f.selector == sig:repay(Midnight.Obligation, uint256, address, bytes).selector
        || f.selector == sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        || f.selector == sig:flashLoan(address, uint256, address, bytes).selector
} {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";

    buyerCallbackCalled = false;

    uint256 balanceBefore = tokenBalances[token][user];

    f(e, args);

    uint256 balanceAfter = tokenBalances[token][user];

    assert balanceAfter < balanceBefore => user == e.msg.sender || callbackReturnedSuccess[user] || signedOfferWithCallbackZero(user);
}
