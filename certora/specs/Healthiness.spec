// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Havoc as havocCallback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;

    /* Assumption: price does not change during rules.
     * Under this assumption we can prove that a healthy borrower cannot get unhealthy by
     * any action on the contract.
     */
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market, chainId, midnight);

    /* Summarize mulDivDown and mulDivUp to simplify the verification task.
     * Use a ghost function that ensures mulDivDown/Up behaves deterministically and
     * add only the axioms about mulDiv that are needed to prove the desired property.
     * The axioms are proved in MulDiv.spec.
     */
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function _.havocAll() external => HAVOC_ALL;

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.onBuy(bytes32 id, Midnight.Market market, address buyer, uint256 buyerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onSell(bytes32 id, Midnight.Market market, address seller, uint256 sellerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onRepay(bytes32 id, Midnight.Market market, uint256 units, address onBehalf, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onLiquidate(bytes32 id, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onFlashLoan(address[] tokens, uint256[] amounts, bytes data) external => genericCallbackBytes32() expect(bytes32);
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDownM(0, b, d) == 0;
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint;

/* Axioms that are proved by MulDiv.spec */

/* proved in mulDivMonotoneA */
definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);

definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);

/* proved in mulDivMonotoneB */
definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => summaryMulDivDownM(a, b1, d) <= summaryMulDivDownM(a, b2, d);

/* proved in mulDivMonotoneD */
definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => summaryMulDivUpM(a, b, d1) >= summaryMulDivUpM(a, b, d2);

/* proved in mulDivAddDownUp */
definition axiomAddDownUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a1, b, d) + summaryMulDivUpM(a2, b, d) >= summaryMulDivDownM(a1 + a2, b, d);

/* proved in mulDivInverseUpDown */
definition axiomInverseUpDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b > 0 && d > 0 => summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b) <= a;

/* proved in mulDivLifLLTV */
definition axiomLifLLTV(mathint a, mathint lif, mathint lltv) returns bool = a >= 0 && lltv * lif <= WAD() * WAD() => summaryMulDivUpM(a, lltv, WAD()) <= summaryMulDivUpM(a, WAD(), lif);

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivDownM(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivUpM(a, b, d));
}

// global variable indicating whether to use the optimized isHealthy() or the bitmap-less implementation
// see callIsHealthy() below.
persistent ghost bool useIsHealthyNoBitmap;

// global variable to track whether the user was healthy before the callbacks.
ghost bool healthyBeforeCallback;

// global variable to track which market and borrower we're testing.
persistent ghost address globalMarketLoanToken;

persistent ghost uint256 globalMarketCollateralLength;

persistent ghost mapping(uint256 => address) globalMarketCollateralOracle;

persistent ghost mapping(uint256 => address) globalMarketCollateralToken;

persistent ghost mapping(uint256 => uint256) globalMarketCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalMarketCollateralMaxLif;

persistent ghost uint256 globalMarketMaturity;

persistent ghost uint256 globalMarketRcfThreshold;

persistent ghost address globalMarketEnterGate;

persistent ghost address globalMarketLiquidatorGate;

persistent ghost bytes32 globalId;

persistent ghost address globalBorrower;

// helper function to check if one of the collateralParams of a market matches the global variables.
// It checks for the length and also returns true if the index is out of bounds. This allows us to require this for every index.
definition collateralMatches(Midnight.Market market, uint256 index) returns bool = (index < globalMarketCollateralLength => market.collateralParams[index].oracle == globalMarketCollateralOracle[index] && market.collateralParams[index].token == globalMarketCollateralToken[index] && market.collateralParams[index].lltv == globalMarketCollateralLLTV[index] && market.collateralParams[index].maxLif == globalMarketCollateralMaxLif[index]);

function equalsGlobalMarket(Midnight.Market market) returns (bool) {
    return market.loanToken == globalMarketLoanToken && market.collateralParams.length == globalMarketCollateralLength && collateralMatches(market, 0) && collateralMatches(market, 1) && collateralMatches(market, 2) && market.maturity == globalMarketMaturity && market.rcfThreshold == globalMarketRcfThreshold && market.enterGate == globalMarketEnterGate && market.liquidatorGate == globalMarketLiquidatorGate;
}

function getGlobalMarket() returns (Midnight.Market) {
    Midnight.Market market;
    require equalsGlobalMarket(market), "get global market";
    return market;
}

function summaryToId(Midnight.Market market, uint256 chainId, address midnight) returns (bytes32) {
    bytes32 id;
    if (equalsGlobalMarket(market) && midnight == currentContract) {
        require id == globalId, "toId() is deterministic";
    } else {
        require id != globalId, "toId() is injective";
    }
    return id;
}

// Call either isHealthy() or isHealthyNoBitmap() depending on global setting.
// We show in CollateralBitmap.spec that both functions return the same value, so calling any of them is okay.
// To avoid the need for bitprecise reasoning, we select for each case the most suitable function, by setting the variable useIsHealthyNoBitmap.
function callIsHealthy(Midnight.Market market, bytes32 id, address borrower) returns (bool) {
    if (useIsHealthyNoBitmap) {
        return isHealthyNoBitmap(market, id, borrower);
    } else {
        return isHealthy(market, id, borrower);
    }
}

// Summary for every callback (token transfer, onLiquidate, onFlashloan, onBuy, onSell)
// we check that the user is healthy before the callback, do some external call (to simulate changes by the callback),
// and then require that the user is still healthy after the callback.
function genericCallback() {
    address dummy;
    env e;
    Midnight.Market globalMarket = getGlobalMarket();

    // check that isHealthy holds before the callback.  We remember any violation and check that none occurred at the end of each rule.
    bool savedHealthyBefore = healthyBeforeCallback && callIsHealthy(globalMarket, globalId, globalBorrower);

    havocCallback.callHavoc(e, dummy);

    // the callback havocs the global variable healthyBeforeCallback, so we restore the variable using the saved value in the local variable.
    healthyBeforeCallback = savedHealthyBefore;

    require callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy after callback";
}

// Same as the summary above except that it also returns a non-deterministic value.
function genericCallbackBool() returns (bool) {
    bool result;
    genericCallback();
    return result;
}

function genericCallbackBytes32() returns (bytes32) {
    bytes32 result;
    genericCallback();
    return result;
}

//// RULES //////

// The remaining rules show that a healthy borrower cannot get unhealthy by calling any function of the contract.
// Since we have a ghost summary for price(), we assume the price will not change during the call.

// To avoid timeouts, we split out two cases for liquidate:
//  1) the borrower under consideration is the one that is liquidated on the market under consideration.
//  2) the borrower is different from the liquidated user, or the market is different.
// and then we have a final rule for all other functions of the contract.

// Show that the user stays healthy on liquidate, if the user gets liquidated (can occur if blocktime exceeds maturity)
rule stayHealthyLiquidateSameBorrower(env e, uint256 collateralIndex, uint256 seizedAssetsIn, uint256 repaidUnitsIn, address receiver, address callbackAddr, bytes data) {
    useIsHealthyNoBitmap = false;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require globalMarketCollateralLLTV[collateralIndex] * globalMarketCollateralMaxLif[collateralIndex] <= WAD() * WAD(), "Proved in lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec: maxLif is at most 1/lltv";

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();

    require callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy before call";

    uint256 collateralBefore = collateral(globalId, globalBorrower, collateralIndex);
    uint256 seizedAssetsOut;
    uint256 repaidUnitsOut;

    seizedAssetsOut, repaidUnitsOut = liquidate(e, globalMarket, collateralIndex, seizedAssetsIn, repaidUnitsIn, globalBorrower, receiver, callbackAddr, data);

    // we cannot use collateral, as it may already have been changed by the callbacks.
    mathint collateralAfter = collateralBefore - seizedAssetsOut;
    mathint price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // require all the axioms that are needed to prove the healthiness after liquidation. These are the same axioms that are proved in the MulDiv.spec
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require axiomInverseUpDown(repaidUnitsOut, globalMarketCollateralMaxLif[collateralIndex], WAD()), "axiom";
    require axiomInverseUpDown(summaryMulDivDownM(repaidUnitsOut, globalMarketCollateralMaxLif[collateralIndex], WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    require axiomLifLLTV(summaryMulDivUpM(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalMarketCollateralMaxLif[collateralIndex], globalMarketCollateralLLTV[collateralIndex]), "axiom";
    require axiomAddDownUp(collateralAfter, seizedAssetsOut, price, ORACLE_PRICE_SCALE()), "axiom";
    require axiomAddDownUp(summaryMulDivDownM(collateralAfter, price, ORACLE_PRICE_SCALE()), summaryMulDivUpM(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalMarketCollateralLLTV[collateralIndex], WAD()), "axiom";

    // check that the user was healthy before all callbacks.  We can only assert this after we included all the needed axioms.
    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy after call";
}

// Show that the user stays healthy on liquidate, if another user gets liquidated or market differs.
rule stayHealthyLiquidateOtherBorrower(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callbackAddr, bytes data) {
    useIsHealthyNoBitmap = true;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();
    require borrower != globalBorrower || !equalsGlobalMarket(market), "borrower or market differs";

    require callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy before call";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callbackAddr, data);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy after call";
}

// Show that the user stays healthy on any other function than liquidate or take.
rule stayHealthy(env e, method f, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector } {
    // for withdraw collateral we choose isHealthy() for all others the isHealthyNoBitmap function.
    useIsHealthyNoBitmap = (f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector);

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";

    require globalMarketCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();

    require callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy before call";

    f(e, args);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalMarket, globalId, globalBorrower), "user is healthy after call";
}
