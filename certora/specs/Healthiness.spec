// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Havoc as havocCallback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;

    // Assumption: price does not change during rules.
    // Under this assumption we can prove that a healthy borrower cannot get unhealthy by any action on the contract.
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market, chainId, midnight);

    // Summarize mulDivDown and mulDivUp to simplify the verification task.
    // Use a ghost function that ensures mulDivDown/Up behaves deterministically and add only the axioms about mulDiv that are needed to prove the desired property.
    // The axioms are proved in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function _.havocAll() external => HAVOC_ALL;

    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    function SafeTransferLib.safeTransfer(address, address, uint256) internal => transferCallback();
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => transferCallback();
    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.onBuy(bytes32 id, Midnight.Market market, uint256 buyerAssets, uint256 units, uint256 pendingFeeIncrease, address buyer, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onSell(bytes32 id, Midnight.Market market, uint256 sellerAssets, uint256 units, uint256 pendingFeeDecrease, address seller, address receiver, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onRepay(bytes32 id, Midnight.Market market, uint256 units, address onBehalf, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onLiquidate(address liquidator, bytes32 id, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, bytes data, uint256 badDebt) external => genericCallbackBytes32() expect(bytes32);
    function _.onFlashLoan(address caller, address[] tokens, uint256[] amounts, bytes data) external => genericCallbackBytes32() expect(bytes32);
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

/* Axioms that are proved by MulDiv.spec */

/* proved in mulDivZero in MulDiv.spec */
definition axiomDownZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivDown(0, b, d) == 0;

/* proved in mulDivMonotoneA */
definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);

definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

/* proved in mulDivMonotoneB */
definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);

/* proved in mulDivMonotoneD */
definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);

/* proved in mulDivAddDownUp */
definition axiomAddDownUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => ghostMulDivDown(a1, b, d) + ghostMulDivUp(a2, b, d) >= ghostMulDivDown(a1 + a2, b, d);

/* proved in mulDivInverseUpDown */
definition axiomInverseUpDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b > 0 && d > 0 => ghostMulDivUp(ghostMulDivDown(a, b, d), d, b) <= a;

/* proved in ExactMath.spec (mulDivLifLLTV) */
definition axiomLifLLTV(mathint a, mathint lif, mathint lltv) returns bool = a >= 0 && lltv * lif <= WAD() * WAD() => ghostMulDivUp(a, lltv, WAD()) <= ghostMulDivUp(a, WAD(), lif);

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
}

// global variable indicating whether to use the optimized isHealthy() or the bitmap-less implementation
// see isHealthyOrLiquidationLocked() below.
persistent ghost bool useIsHealthyNoBitmap;

// global variable to track whether the user was healthy before the callbacks.
// Persistent so its value survives the havoc of unresolved external calls inside callbacks.
persistent ghost bool healthyOrLockedBeforeCallbacks;

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

// This function returns true iff the user is healthy or locked from liquidations.
// It calls either isHealthy() or isHealthyNoBitmap() depending on global setting.
// We show in CollateralBitmap.spec that both functions return the same value, so calling any of them is okay.
// To avoid the need for bitprecise reasoning, we select for each case the most suitable function, by setting the variable useIsHealthyNoBitmap.
//
// Rule of thumb for picking the summary:
//  - If the function under verification calls isHealthy() itself (e.g. withdrawCollateral, take)
//    or inlines its computation over the collateral bitmap (e.g. liquidate, when proving the same
//    borrower stays healthy), keep isHealthy() so the prover can directly match the spec's
//    `assert isHealthy` against the health check in the code.
//  - For functions that don't perform an isHealthy() check (e.g. supplyCollateral, repay, borrow),
//    use isHealthyNoBitmap() so the prover reasons about the explicit sum of LLTV-weighted
//    collateral values over all collateralParams, without having to follow the bitmap iteration.
//    For example, for supplyCollateral, the prover just needs to see that the sum is increased.
function isHealthyOrLiquidationLocked(Midnight.Market market, bytes32 id, address borrower) returns (bool) {
    if (useIsHealthyNoBitmap) {
        return isHealthyNoBitmap(market, id, borrower) || liquidationLocked(id, borrower);
    } else {
        return isHealthy(market, id, borrower) || liquidationLocked(id, borrower);
    }
}

// Summary for every non-transfer callback (onLiquidate, onFlashloan, onBuy, onSell, etc.)
// we check that the user is healthy or locked before the callback, do some external call (to simulate changes by the callback),
// and then require that the user is still healthy or locked after the callback.
// healthyOrLockedBeforeCallbacks is persistent, so it survives the havoc and doesn't need to be saved/restored.
function genericCallback() {
    address dummy;
    env e;
    Midnight.Market globalMarket = getGlobalMarket();

    // check that isHealthy or locked holds before the callback.  We remember any violation and check that none occurred at the end of each rule.
    bool liquidationLockedBefore = liquidationLocked(globalId, globalBorrower);
    healthyOrLockedBeforeCallbacks = healthyOrLockedBeforeCallbacks && isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower);

    havocCallback.callHavoc(e, dummy);

    require liquidationLocked(globalId, globalBorrower) == liquidationLockedBefore, "liquidationLocked is preserved over calls";
    require isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked after callback";
}

// Lighter summary for token transfer callbacks (safeTransfer, safeTransferFrom).
// Skips the "before" isHealthy check (which genericCallback does) to halve the isHealthy
// evaluation cost per transfer, avoiding timeouts.  Still models reentrancy via havoc and
// requires healthiness after the callback. The "before" check for subsequent genericCallback
// invocations (e.g. onLiquidate) will catch any violation that occurred between callbacks.
function transferCallback() {
    address dummy;
    env e;
    Midnight.Market globalMarket = getGlobalMarket();

    bool liquidationLockedBefore = liquidationLocked(globalId, globalBorrower);

    havocCallback.callHavoc(e, dummy);

    require liquidationLocked(globalId, globalBorrower) == liquidationLockedBefore, "liquidationLocked is preserved over calls";
    require isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked after callback";
}

// Same as genericCallback except that it also returns a non-deterministic value.
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

// The precise invariant we show is
//    `isHealthy(globalMarket, globalId, globalBorrower) || liquidationLocked(globalId, globalBorrower)`
// which is also true during the callbacks in take().

// To avoid timeouts, we split out two cases for liquidate:
//  1) the borrower under consideration is the one that is liquidated on the market under consideration.
//  2) the borrower is different from the liquidated user, or the market is different.
// and then we have a final rule for all other functions of the contract.

// Show that the user stays healthy on liquidate, if the user gets liquidated (can occur if blocktime exceeds maturity)
rule stayHealthyLiquidateSameBorrower(env e, uint256 collateralIndex, uint256 seizedAssetsIn, uint256 repaidUnitsIn, address receiver, address callbackAddr, bytes data, bool postMaturityMode) {
    useIsHealthyNoBitmap = false;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyOrLockedBeforeCallbacks = true;

    require globalMarketCollateralLLTV[collateralIndex] * globalMarketCollateralMaxLif[collateralIndex] <= WAD() * WAD(), "Proved in lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec: maxLif is at most 1/lltv";

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();

    require isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked before call";

    uint256 collateralBefore = collateral(globalId, globalBorrower, collateralIndex);
    uint256 seizedAssetsOut;
    uint256 repaidUnitsOut;

    seizedAssetsOut, repaidUnitsOut = liquidate(e, globalMarket, collateralIndex, seizedAssetsIn, repaidUnitsIn, globalBorrower, postMaturityMode, receiver, callbackAddr, data);

    // we cannot use collateral, as it may already have been changed by the callbacks.
    mathint collateralAfter = collateralBefore - seizedAssetsOut;
    mathint price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // require all the axioms that are needed to prove the healthiness after liquidation. These are the same axioms that are proved in the MulDiv.spec
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2), "axiom";
    require axiomDownZero(price, ORACLE_PRICE_SCALE()), "axiom";
    require axiomDownZero(globalMarketCollateralLLTV[collateralIndex], WAD()), "axiom";
    require axiomInverseUpDown(repaidUnitsOut, globalMarketCollateralMaxLif[collateralIndex], WAD()), "axiom";
    require axiomInverseUpDown(ghostMulDivDown(repaidUnitsOut, globalMarketCollateralMaxLif[collateralIndex], WAD()), ORACLE_PRICE_SCALE(), price), "axiom";
    require axiomLifLLTV(ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalMarketCollateralMaxLif[collateralIndex], globalMarketCollateralLLTV[collateralIndex]), "axiom";
    require axiomAddDownUp(collateralAfter, seizedAssetsOut, price, ORACLE_PRICE_SCALE()), "axiom";
    require axiomAddDownUp(ghostMulDivDown(collateralAfter, price, ORACLE_PRICE_SCALE()), ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), globalMarketCollateralLLTV[collateralIndex], WAD()), "axiom";

    // check that the user was healthy before all callbacks.  We can only assert this after we included all the needed axioms.
    assert healthyOrLockedBeforeCallbacks, "user is healthy or locked before callbacks";
    assert isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked after call";
}

// Show that the user stays healthy on liquidate, if another user gets liquidated or market differs.
rule stayHealthyLiquidateOtherBorrower(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callbackAddr, bytes data, bool postMaturityMode) {
    useIsHealthyNoBitmap = true;

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyOrLockedBeforeCallbacks = true;

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();
    require borrower != globalBorrower || !equalsGlobalMarket(market), "borrower or market differs";

    require isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked before call";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callbackAddr, data);

    assert healthyOrLockedBeforeCallbacks, "user is healthy or locked before callbacks";
    assert isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked after call";
}

// Show that the user stays healthy on any other function than liquidate.
// We also allow the user to be liquidationLocked() (for callbacks from take(), where the seller
// is not required to be healthy).
rule stayHealthyOrLocked(env e, method f, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    // for withdraw collateral and take we choose isHealthy() for all others the isHealthyNoBitmap function.
    useIsHealthyNoBitmap = (f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector);

    // This variable is set to false whenever isHealthy() is violated before a callback.  Initially we set it to true to indicate no violations detected.
    healthyOrLockedBeforeCallbacks = true;

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d), "axiom";

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    Midnight.Market globalMarket = getGlobalMarket();

    require isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked before call";

    f(e, args);

    assert healthyOrLockedBeforeCallbacks, "user is healthy or locked before callbacks";
    assert isHealthyOrLiquidationLocked(globalMarket, globalId, globalBorrower), "user is healthy or locked after call";
}

// Show that liquidationLocked flag is preserved over calls
// By induction this allows us to assume that liquidationLocked is preserved over callbacks.
rule liquidationLockedPreserved(env e, method f, calldataarg args) {
    bool liquidationLockedBefore = liquidationLocked(globalId, globalBorrower);

    f(e, args);

    assert liquidationLocked(globalId, globalBorrower) == liquidationLockedBefore;
}

// Show that by the end of a transactions the global borrower is not liquidation locked.
weak invariant notLiquidationLocked()
    !liquidationLocked(globalId, globalBorrower);

// Check that locked positions cannot be liquidated: for any liquidate() parameters
// (other than the global market and borrower), the call must revert when the borrower
// is liquidationLocked.
rule notLiquidatableWhenLocked(env e, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address receiver, address callbackAddr, bytes data, bool postMaturityMode) {
    Midnight.Market globalMarket = getGlobalMarket();

    require liquidationLocked(globalId, globalBorrower), "borrower is locked";

    liquidate@withrevert(e, globalMarket, collateralIndex, seizedAssets, repaidUnits, globalBorrower, postMaturityMode, receiver, callbackAddr, data);

    assert lastReverted, "liquidate must revert on a locked borrower";
}
