// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

methods {
    // These functions are over-approximated: it explores more paths, and the arithmetic does not decide which external calls are made.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
}

// Number of CALLs executed by Midnight to each address.
persistent ghost mapping(address => mathint) callsTo;

// True for each address that Midnight STATICCALLs.
persistent ghost mapping(address => bool) staticCalled;

// True for each address that Midnight DELEGATECALLs.
persistent ghost mapping(address => bool) delegateCalled;

// True when Midnight sends ETH, or executes a CALLCODE.
persistent ghost bool otherCall;

// Unresolved external calls are not executed, so these hooks only see the calls executed by Midnight itself, not the ones of its callees.
hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    callsTo[addr] = callsTo[addr] + 1;
    otherCall = otherCall || value != 0;
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    staticCalled[addr] = true;
}

hook DELEGATECALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    delegateCalled[addr] = true;
}

hook CALLCODE(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    otherCall = true;
}

function setUp() {
    require(forall address a. callsTo[a] == 0, "set up the initial ghost state");
    require(forall address a. !staticCalled[a], "set up the initial ghost state");
    require(forall address a. !delegateCalled[a], "set up the initial ghost state");
    require(!otherCall, "set up the initial ghost state");
}

definition isOracle(Midnight.Market market, address a) returns bool = exists uint256 i. i < market.collateralParams.length && market.collateralParams[i].oracle == a;

// Check that withdraw only calls the loan token, once (transfer to the receiver).
rule withdrawCalls(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    setUp();

    withdraw(e, market, units, onBehalf, receiver);

    assert callsTo[market.loanToken] == 1;
    assert forall address a. a != market.loanToken => callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that take calls the loan token twice (transfers to Midnight and to the receiver), the buyer callback and the seller callback if they are set, and only view calls the ratifier, the enter gate and the market's oracles.
rule takeCalls(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    setUp();

    address buyerCallback = offer.buy ? offer.callback : takerCallback;
    address sellerCallback = offer.buy ? takerCallback : offer.callback;

    address loanToken = offer.market.loanToken;
    require(loanToken != 0 && buyerCallback != loanToken && sellerCallback != loanToken && (buyerCallback == 0 || buyerCallback != sellerCallback), "distinct targets, to count the calls to each of them");

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert callsTo[loanToken] == 2;
    assert buyerCallback != 0 => callsTo[buyerCallback] == 1;
    assert sellerCallback != 0 => callsTo[sellerCallback] == 1;
    assert callsTo[0] == 0;
    assert forall address a. a != loanToken && a != buyerCallback && a != sellerCallback => callsTo[a] == 0;
    assert staticCalled[offer.ratifier];
    assert forall address a. staticCalled[a] => a == offer.ratifier || (a != 0 && a == offer.market.enterGate) || isOracle(offer.market, a);
}

// Check that repay calls the loan token once (transfer from the payer), and the callback if it is set.
rule repayCalls(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    setUp();

    require(market.loanToken != 0 && callback != market.loanToken, "distinct targets, to count the calls to each of them");

    repay(e, market, units, onBehalf, callback, data);

    assert callsTo[market.loanToken] == 1;
    assert callback != 0 => callsTo[callback] == 1;
    assert callsTo[0] == 0;
    assert forall address a. a != market.loanToken && a != callback => callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that supplyCollateral calls the collateral token once (transfer from the caller), and only view calls the oracle of that collateral.
rule supplyCollateralCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) {
    setUp();

    supplyCollateral(e, market, collateralIndex, assets, onBehalf);

    assert callsTo[market.collateralParams[collateralIndex].token] == 1;
    assert forall address a. a != market.collateralParams[collateralIndex].token => callsTo[a] == 0;
    assert forall address a. staticCalled[a] => a == market.collateralParams[collateralIndex].oracle;
}

// Check that withdrawCollateral calls the collateral token once (transfer to the receiver), and only view calls the market's oracles.
rule withdrawCollateralCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    setUp();

    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);

    assert callsTo[market.collateralParams[collateralIndex].token] == 1;
    assert forall address a. a != market.collateralParams[collateralIndex].token => callsTo[a] == 0;
    assert forall address a. staticCalled[a] => isOracle(market, a);
}

// Check that liquidate calls the seized collateral token once (transfer to the receiver), the loan token once (transfer from the payer) and the callback if it is set, and only view calls the liquidator gate and the market's oracles.
rule liquidateCalls(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    setUp();

    address collateralToken = market.collateralParams[collateralIndex].token;
    require(collateralToken != 0 && market.loanToken != 0 && collateralToken != market.loanToken && callback != collateralToken && callback != market.loanToken, "distinct targets, to count the calls to each of them");

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert callsTo[collateralToken] == 1;
    assert callsTo[market.loanToken] == 1;
    assert callback != 0 => callsTo[callback] == 1;
    assert callsTo[0] == 0;
    assert forall address a. a != collateralToken && a != market.loanToken && a != callback => callsTo[a] == 0;
    assert forall address a. staticCalled[a] => (a != 0 && a == market.liquidatorGate) || isOracle(market, a);
}

// Check that flashLoan calls each token twice (transfers to and from the callback) and the callback once.
rule flashLoanCalls(env e, address[] tokens, uint256[] assets, address callback, bytes data) {
    setUp();

    require(forall uint256 i. forall uint256 j. i < j && j < tokens.length => tokens[i] != tokens[j], "distinct targets, to count the calls to each of them");
    require(forall uint256 i. i < tokens.length => tokens[i] != callback, "distinct targets, to count the calls to each of them");

    flashLoan(e, tokens, assets, callback, data);

    assert callsTo[callback] == 1;
    assert forall uint256 i. i < tokens.length => callsTo[tokens[i]] == 2;
    assert forall address a. a != callback && (forall uint256 i. i < tokens.length => tokens[i] != a) => callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that claimSettlementFee only calls the token, once (transfer to the receiver).
rule claimSettlementFeeCalls(env e, address token, uint256 amount, address receiver) {
    setUp();

    claimSettlementFee(e, token, amount, receiver);

    assert callsTo[token] == 1;
    assert forall address a. a != token => callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that claimContinuousFee only calls the loan token, once (transfer to the receiver).
rule claimContinuousFeeCalls(env e, Midnight.Market market, uint256 amount, address receiver) {
    setUp();

    claimContinuousFee(e, market, amount, receiver);

    assert callsTo[market.loanToken] == 1;
    assert forall address a. a != market.loanToken => callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that isHealthy only view calls the market's oracles.
rule isHealthyCalls(env e, Midnight.Market market, bytes32 id, address borrower) {
    setUp();

    isHealthy(e, market, id, borrower);

    assert forall address a. callsTo[a] == 0;
    assert forall address a. staticCalled[a] => isOracle(market, a);
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
        && f.selector != sig:multicall(bytes[]).selector
} {
    setUp();

    f(e, args);

    assert forall address a. callsTo[a] == 0;
    assert forall address a. !staticCalled[a];
}

// Check that multicall delegate calls Midnight itself, so it makes the external calls of the batched entry points.
rule multicallCalls(env e, bytes[] calls) {
    setUp();

    multicall(e, calls);

    assert calls.length > 0 => delegateCalled[currentContract];
}

// Check that Midnight never sends ETH, never executes a CALLCODE, and only delegate calls itself, in multicall.
rule noOtherCall(env e, method f, calldataarg args) {
    setUp();

    f(e, args);

    assert forall address a. delegateCalled[a] => a == currentContract && f.selector == sig:multicall(bytes[]).selector;
    assert !otherCall;
}
