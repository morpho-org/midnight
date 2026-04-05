// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Havoc as callback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Obligation, bytes32, address) external returns (bool) envfree;

    /* Assumption: price does not change during rules.
     * Under this assumption we can prove that a borrower who is not liquidatable
     * stays not liquidatable during callbacks and after any successful action.
     */
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes32) => summaryToId(obligation, chainId, morpho);

    /* Summarize mulDivDown and mulDivUp to simplify the verification task.
     * Use a ghost function that ensures mulDivDown/Up behaves deterministically.
     */
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function _.havocAll() external => HAVOC_ALL;

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.onBuy(bytes32 id, Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onSell(bytes32 id, Midnight.Obligation obligation, address seller, uint256 sellerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onRepay(bytes32 id, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) external => genericCallback() expect void;
    function _.onLiquidate(bytes32 id, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallback() expect void;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => genericCallback() expect void;
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

// global variable indicating whether to use the optimized isHealthy() or the bitmap-less implementation.
persistent ghost bool useIsHealthyNoBitmap;

// global variable to remember the block timestamp of the outer call.
persistent ghost uint256 globalBlockTimestamp;

// global variable to track whether the user was not liquidatable before the callbacks.
ghost bool notLiquidatableBeforeCallback;

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

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address morpho) returns (bytes32) {
    bytes32 id;
    if (equalsGlobalObligation(obligation) && morpho == currentContract) {
        require id == globalId, "toId() is deterministic";
    } else {
        require id != globalId, "toId() is injective";
    }
    return id;
}

// Call either isHealthy() or isHealthyNoBitmap() depending on global setting.
// We show in CollateralBitmap.spec that both functions return the same value, so calling any of them is okay.
function callIsHealthy(Midnight.Obligation obligation, bytes32 id, address borrower) returns (bool) {
    if (useIsHealthyNoBitmap) {
        return isHealthyNoBitmap(obligation, id, borrower);
    } else {
        return isHealthy(obligation, id, borrower);
    }
}

function callIsLiquidatable(Midnight.Obligation obligation, bytes32 id, address borrower) returns (bool) {
    return !liquidationLocked(id, borrower) && (!callIsHealthy(obligation, id, borrower) || globalBlockTimestamp > obligation.maturity);
}

function callIsNotLiquidatable(Midnight.Obligation obligation, bytes32 id, address borrower) returns (bool) {
    return !callIsLiquidatable(obligation, id, borrower);
}

definition takeSeller(address taker, Midnight.Offer offer) returns address = offer.buy ? taker : offer.maker;

// Summary for every callback (token transfer, onLiquidate, onFlashloan, onBuy, onSell).
// We check that the tracked borrower is not liquidatable before the callback, do some external call
// (to simulate changes by the callback), and then require that the borrower is still not liquidatable after the callback.
function genericCallback() {
    address dummy;
    env e;
    Midnight.Obligation globalObligation = getGlobalObligation();

    bool savedNotLiquidatableBefore = notLiquidatableBeforeCallback && callIsNotLiquidatable(globalObligation, globalId, globalBorrower);

    callback.callHavoc(e, dummy);

    // the callback havocs the global variable notLiquidatableBeforeCallback, so we restore it using the saved local variable.
    notLiquidatableBeforeCallback = savedNotLiquidatableBefore;

    require callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable after callback";
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

// The remaining rules show that a borrower who is not liquidatable before a call stays not liquidatable
// during callbacks and after any successful call. We split out liquidate and take to keep the proof manageable.

// Show that the borrower stays not liquidatable on liquidate, if another user gets liquidated or the obligation differs.
rule stayNotLiquidatableLiquidateOtherBorrower(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    useIsHealthyNoBitmap = true;
    globalBlockTimestamp = e.block.timestamp;

    // This variable is set to false whenever not liquidatable is violated before a callback. Initially we set it to true.
    notLiquidatableBeforeCallback = true;

    require globalObligationCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();
    require borrower != globalBorrower || !equalsGlobalObligation(obligation), "borrower or obligation differs";

    require callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable before call";

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert notLiquidatableBeforeCallback, "user is not liquidatable before callbacks";
    assert callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable after call";
}

// Show that the borrower stays not liquidatable on take, if the borrower under consideration is the seller on the obligation under consideration.
rule stayNotLiquidatableTakeSameSeller(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    useIsHealthyNoBitmap = true;
    globalBlockTimestamp = e.block.timestamp;

    // This variable is set to false whenever not liquidatable is violated before a callback. Initially we set it to true.
    notLiquidatableBeforeCallback = true;

    require globalObligationCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();
    require equalsGlobalObligation(offer.obligation), "obligation matches";
    require takeSeller(taker, offer) == globalBorrower, "seller matches";

    require callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable before call";

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert notLiquidatableBeforeCallback, "user is not liquidatable before callbacks";
    assert callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable after call";
}

// Show that the borrower stays not liquidatable on take, if another user is the seller or the obligation differs.
rule stayNotLiquidatableTakeOtherBorrower(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    useIsHealthyNoBitmap = true;
    globalBlockTimestamp = e.block.timestamp;

    // This variable is set to false whenever not liquidatable is violated before a callback. Initially we set it to true.
    notLiquidatableBeforeCallback = true;

    require globalObligationCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();
    require takeSeller(taker, offer) != globalBorrower || !equalsGlobalObligation(offer.obligation), "seller or obligation differs";

    require callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable before call";

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert notLiquidatableBeforeCallback, "user is not liquidatable before callbacks";
    assert callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable after call";
}

// Show that the borrower stays not liquidatable on any other function than liquidate or take.
rule stayNotLiquidatable(env e, method f, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    // For withdraw collateral we choose isHealthy(); for all others we choose the bitmap-less implementation.
    useIsHealthyNoBitmap = (f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector);
    globalBlockTimestamp = e.block.timestamp;

    // This variable is set to false whenever not liquidatable is violated before a callback. Initially we set it to true.
    notLiquidatableBeforeCallback = true;

    require globalObligationCollateralLength <= 3, "too many collateralParams for the spec to handle";

    Midnight.Obligation globalObligation = getGlobalObligation();

    require callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable before call";

    f(e, args);

    assert notLiquidatableBeforeCallback, "user is not liquidatable before callbacks";
    assert callIsNotLiquidatable(globalObligation, globalId, globalBorrower), "user is not liquidatable after call";
}
