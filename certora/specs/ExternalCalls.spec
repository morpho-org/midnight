// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // These functions are over-approximated: it explores more paths, and the arithmetic does not decide which external calls are made.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
}

// Number of CALLs executed by Midnight.
persistent ghost mathint callCount;

// True for each address that Midnight CALLs.
persistent ghost mapping(address => bool) called;

// True for each address that Midnight STATICCALLs.
persistent ghost mapping(address => bool) staticCalled;

// True when Midnight sends ETH, or executes a DELEGATECALL or a CALLCODE.
persistent ghost bool otherCall;

// Unresolved external calls are not executed, so these hooks only see the calls executed by Midnight itself, not the ones of its callees.
hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    callCount = callCount + 1;
    called[addr] = true;
    otherCall = otherCall || value != 0;
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    staticCalled[addr] = true;
}

hook DELEGATECALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    otherCall = true;
}

hook CALLCODE(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    otherCall = true;
}

function setUp() {
    require(callCount == 0, "set up the initial ghost state");
    require(forall address a. !called[a], "set up the initial ghost state");
    require(forall address a. !staticCalled[a], "set up the initial ghost state");
    require(!otherCall, "set up the initial ghost state");
}

definition isOracle(Midnight.Market market, address a) returns bool = exists uint256 i. i < market.collateralParams.length && market.collateralParams[i].oracle == a;

// Check that withdraw only calls the loan token, once (transfer to the receiver).
rule withdrawCalls(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    setUp();

    withdraw(e, market, units, onBehalf, receiver);

    assert callCount == 1;
    assert forall address a. called[a] => a == market.loanToken;
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}

// Check that take calls the loan token twice (transfers to Midnight and to the receiver), the buyer callback and the seller callback if they are set, and only view calls the ratifier, the enter gate and the market's oracles.
rule takeCalls(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    setUp();

    address buyerCallback = offer.buy ? offer.callback : takerCallback;
    address sellerCallback = offer.buy ? takerCallback : offer.callback;

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert callCount == 2 + (buyerCallback != 0 ? 1 : 0) + (sellerCallback != 0 ? 1 : 0);
    assert forall address a. called[a] => a == offer.market.loanToken || (a != 0 && (a == buyerCallback || a == sellerCallback));
    assert staticCalled[offer.ratifier];
    assert forall address a. staticCalled[a] => a == offer.ratifier || (a != 0 && a == offer.market.enterGate) || isOracle(offer.market, a);
    assert !otherCall;
}

// Check that repay calls the loan token once (transfer from the payer), and the callback if it is set.
rule repayCalls(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    setUp();

    repay(e, market, units, onBehalf, callback, data);

    assert callCount == 1 + (callback != 0 ? 1 : 0);
    assert forall address a. called[a] => a == market.loanToken || (a != 0 && a == callback);
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}

// Check that supplyCollateral calls the collateral token once (transfer from the caller), and only view calls the oracle of that collateral.
rule supplyCollateralCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) {
    setUp();

    supplyCollateral(e, market, collateralIndex, assets, onBehalf);

    assert callCount == 1;
    assert forall address a. called[a] => a == market.collateralParams[collateralIndex].token;
    assert forall address a. staticCalled[a] => a == market.collateralParams[collateralIndex].oracle;
    assert !otherCall;
}

// Check that withdrawCollateral calls the collateral token once (transfer to the receiver), and only view calls the market's oracles.
rule withdrawCollateralCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    setUp();

    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);

    assert callCount == 1;
    assert forall address a. called[a] => a == market.collateralParams[collateralIndex].token;
    assert forall address a. staticCalled[a] => isOracle(market, a);
    assert !otherCall;
}

// Check that liquidate calls the seized collateral token once (transfer to the receiver), the loan token once (transfer from the payer) and the callback if it is set, and only view calls the liquidator gate and the market's oracles.
rule liquidateCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    setUp();

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert callCount == 2 + (callback != 0 ? 1 : 0);
    assert forall address a. called[a] => a == market.collateralParams[collateralIndex].token || a == market.loanToken || (a != 0 && a == callback);
    assert forall address a. staticCalled[a] => (a != 0 && a == market.liquidatorGate) || isOracle(market, a);
    assert !otherCall;
}

// Check that flashLoan calls each token twice (transfers to and from the callback) and the callback once.
rule flashLoanCalls(env e, address[] tokens, uint256[] assets, address callback, bytes data) {
    setUp();

    flashLoan(e, tokens, assets, callback, data);

    assert callCount == 2 * tokens.length + 1;
    assert forall address a. called[a] => a == callback || (exists uint256 i. i < tokens.length && tokens[i] == a);
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}

// Check that claimSettlementFee only calls the token, once (transfer to the receiver).
rule claimSettlementFeeCalls(env e, address token, uint256 amount, address receiver) {
    setUp();

    claimSettlementFee(e, token, amount, receiver);

    assert callCount == 1;
    assert forall address a. called[a] => a == token;
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}

// Check that claimContinuousFee only calls the loan token, once (transfer to the receiver).
rule claimContinuousFeeCalls(env e, Midnight.Market market, uint256 amount, address receiver) {
    setUp();

    claimContinuousFee(e, market, amount, receiver);

    assert callCount == 1;
    assert forall address a. called[a] => a == market.loanToken;
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}

// Check that isHealthy only view calls the market's oracles.
rule isHealthyCalls(env e, Midnight.Market market, bytes32 id, address borrower) {
    setUp();

    isHealthy(e, market, id, borrower);

    assert callCount == 0;
    assert forall address a. staticCalled[a] => isOracle(market, a);
    assert !otherCall;
}

// Check that the other functions make no external call.
rule noExternalCall(method f, env e, calldataarg args)
filtered {
    f -> f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
        && f.selector != sig:flashLoan(address[], uint256[], address, bytes).selector
        && f.selector != sig:claimSettlementFee(address, uint256, address).selector
        && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector
        && f.selector != sig:isHealthy(Midnight.Market, bytes32, address).selector
} {
    setUp();

    f(e, args);

    assert callCount == 0;
    assert forall address a. !staticCalled[a];
    assert !otherCall;
}
