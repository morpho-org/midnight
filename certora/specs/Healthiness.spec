// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Havoc as havocCallback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Obligation, bytes32, address) external returns (bool) envfree;

    /* Assumption: price does not change during rules.
     * Under this assumption we can prove that a healthy borrower cannot get unhealthy by
     * any action on the contract.
     */
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation, chainId, midnight);

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
    function _.onBuy(bytes32 id, Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onSell(bytes32 id, Midnight.Obligation obligation, address seller, uint256 sellerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onRepay(bytes32 id, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onLiquidate(bytes32 id, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallbackBytes32() expect(bytes32);
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

// global variable to track which obligation and borrower we're testing.
persistent ghost address globalObligationLoanToken;

persistent ghost uint256 globalObligationCollateralLength;

persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;

persistent ghost mapping(uint256 => address) globalObligationCollateralToken;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralMaxLif;

persistent ghost uint256 globalObligationMaturity;

persistent ghost uint256 globalObligationRcfThreshold;

persistent ghost address globalObligationEnterGate;

persistent ghost address globalObligationLiquidatorGate;

persistent ghost bytes32 globalId;

persistent ghost address globalBorrower;

// helper function to check if one of the collateralParams of an obligation matches the global variables.
// It checks for the length and also returns true if the index is out of bounds. This allows us to require this for every index.
definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool = (index < globalObligationCollateralLength => obligation.collateralParams[index].oracle == globalObligationCollateralOracle[index] && obligation.collateralParams[index].token == globalObligationCollateralToken[index] && obligation.collateralParams[index].lltv == globalObligationCollateralLLTV[index] && obligation.collateralParams[index].maxLif == globalObligationCollateralMaxLif[index]);

function equalsGlobalObligation(Midnight.Obligation obligation) returns (bool) {
    return obligation.loanToken == globalObligationLoanToken && obligation.collateralParams.length == globalObligationCollateralLength && collateralMatches(obligation, 0) && collateralMatches(obligation, 1) && collateralMatches(obligation, 2) && obligation.maturity == globalObligationMaturity && obligation.rcfThreshold == globalObligationRcfThreshold && obligation.enterGate == globalObligationEnterGate && obligation.liquidatorGate == globalObligationLiquidatorGate;
}

function getGlobalObligation() returns (Midnight.Obligation) {
    Midnight.Obligation obligation;
    require equalsGlobalObligation(obligation), "get global obligation";
    return obligation;
}

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns (bytes32) {
    bytes32 id;
    if (equalsGlobalObligation(obligation) && midnight == currentContract) {
        require id == globalId, "toId() is deterministic";
    } else {
        require id != globalId, "toId() is injective";
    }
    return id;
}

// Call either isHealthy() or isHealthyNoBitmap() depending on global setting.
// We show in CollateralBitmap.spec that both functions return the same value, so calling any of them is okay.
// To avoid the need for bitprecise reasoning, we select for each case the most suitable function, by setting the variable useIsHealthyNoBitmap.
function callIsHealthy(Midnight.Obligation obligation, bytes32 id, address borrower) returns (bool) {
    if (useIsHealthyNoBitmap) {
        return isHealthyNoBitmap(obligation, id, borrower);
    } else {
        return isHealthy(obligation, id, borrower);
    }
}

// Summary for every callback (token transfer, onLiquidate, onFlashloan, onBuy, onSell)
// we check that the user is healthy before the callback, do some external call (to simulate changes by the callback),
// and then require that the user is still healthy after the callback.
function genericCallback() {
    address dummy;
    env e;
    Midnight.Obligation globalObligation = getGlobalObligation();

    // check that isHealthy holds before the callback.  We remember any violation and check that none occurred at the end of each rule.
    bool savedHealthyBefore = healthyBeforeCallback && callIsHealthy(globalObligation, globalId, globalBorrower);

    havocCallback.callHavoc(e, dummy);

    // the callback havocs the global variable healthyBeforeCallback, so we restore the variable using the saved value in the local variable.
    healthyBeforeCallback = savedHealthyBefore;

    require callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy after callback";
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
//  1) the borrower under consideration is the one that is liquidated on the obligation under consideration.
//  2) the borrower is different from the liquidated user, or the obligation is different.
// and then we have a final rule for all other functions of the contract.

// Show that the user stays healthy on liquidate, if the user gets liquidated (can occur if blocktime exceeds maturity)
rule stayHealthyLiquidateSameBorrower(env e, uint256 collateralIndex, uint256 seizedAssetsIn, uint256 repaidUnitsIn, address receiver, address callbackAddr, bytes data) {
    useIsHealthyNoBitmap = false;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require globalObligationCollateralLLTV[collateralIndex] * globalObligationCollateralMaxLif[collateralIndex] <= WAD() * WAD(), "Proved in lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec: maxLif is at most 1/lltv";

    require globalObligationCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();

    require callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy before call";

    uint256 collateralBefore = collateral(globalId, globalBorrower, collateralIndex);
    uint256 seizedAssetsOut;
    uint256 repaidUnitsOut;

    seizedAssetsOut, repaidUnitsOut = liquidate(e, globalObligation, collateralIndex, seizedAssetsIn, repaidUnitsIn, globalBorrower, receiver, callbackAddr, data);

    // we cannot use collateral, as it may already have been changed by the callbacks.
    mathint collateralAfter = collateralBefore - seizedAssetsOut;
    mathint price = summaryPrice(globalObligation.collateralParams[collateralIndex].oracle);

    // require all the axioms that are needed to prove the healthiness after liquidation. These are the same axioms that are proved in the MulDiv.spec
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require axiomInverseUpDown(repaidUnitsOut, globalObligationCollateralMaxLif[collateralIndex], WAD()), "axiom";
    require axiomInverseUpDown(summaryMulDivDownM(repaidUnitsOut, globalObligationCollateralMaxLif[collateralIndex], WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    require axiomLifLLTV(summaryMulDivUpM(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalObligationCollateralMaxLif[collateralIndex], globalObligationCollateralLLTV[collateralIndex]), "axiom";
    require axiomAddDownUp(collateralAfter, seizedAssetsOut, price, ORACLE_PRICE_SCALE()), "axiom";
    require axiomAddDownUp(summaryMulDivDownM(collateralAfter, price, ORACLE_PRICE_SCALE()), summaryMulDivUpM(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalObligationCollateralLLTV[collateralIndex], WAD()), "axiom";

    // check that the user was healthy before all callbacks.  We can only assert this after we included all the needed axioms.
    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy after call";
}

// Show that the user stays healthy on liquidate, if another user gets liquidated or obligation differs.
rule stayHealthyLiquidateOtherBorrower(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callbackAddr, bytes data) {
    useIsHealthyNoBitmap = true;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require globalObligationCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();
    require borrower != globalBorrower || !equalsGlobalObligation(obligation), "borrower or obligation differs";

    require callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy before call";

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callbackAddr, data);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy after call";
}

// Show that the user stays healthy on any other function than liquidate or take.
rule stayHealthy(env e, method f, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    // for withdraw collateral we choose isHealthy() for all others the isHealthyNoBitmap function.
    useIsHealthyNoBitmap = (f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector);

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyBeforeCallback = true;

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";

    require globalObligationCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();

    require callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy before call";

    f(e, args);

    assert healthyBeforeCallback, "user is healthy before callbacks";
    assert callIsHealthy(globalObligation, globalId, globalBorrower), "user is healthy after call";
}
