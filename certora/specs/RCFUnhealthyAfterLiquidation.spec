// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;

    /* Assumption: price does not change during rules. */
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market, chainId, midnight);

    /* Summarize mulDivDown and mulDivUp with tight floor/ceil axioms so the ghosts
     * behave like real integer division. The axioms are proved in MulDiv.spec.
     */
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    function _.transferFrom(address from, address to, uint256 amount) external => NONDET;
    function _.transfer(address to, uint256 amount) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
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

/* Axioms exposed as definitions so each rule opts in via `require forall ... axiomX(...)`.
 * Keeps quantifier instantiation scoped to the rules that need each axiom.
 * Proved in MulDiv.spec.
 */

/* floor lower bound: mulDivDown(a, b, d) * d <= a * b */
definition axiomDownLowerBound(mathint a, mathint b, mathint d) returns bool =
    0 <= a && 0 <= b && 0 < d => summaryMulDivDownM(a, b, d) * d <= a * b;

/* floor strictness: (mulDivDown(a, b, d) + 1) * d > a * b — pins the ghost to the
 * actual floor of a*b/d. Without this the SMT can under-approximate and pick 0. */
definition axiomDownStrictness(mathint a, mathint b, mathint d) returns bool =
    0 <= a && 0 <= b && 0 < d => (summaryMulDivDownM(a, b, d) + 1) * d > a * b;

/* ceil upper bound: mulDivUp(a, b, d) * d >= a * b */
definition axiomUpUpperBound(mathint a, mathint b, mathint d) returns bool =
    0 <= a && 0 <= b && 0 < d => summaryMulDivUpM(a, b, d) * d >= a * b;

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

//// RULES //////

// Concrete-market version of healthyAfterMaxRcfLiquidationSingleCollateral:
// pins every globalMarket* ghost to a specific value so the obligation is fully
// determined. Useful as a sanity check and as a faster-to-verify variant.
rule concreteHealthyAfterMaxRcfLiquidationSingleCollateral(env e, uint256 seizedAssets, uint256 repaidUnits, address receiver, address callbackAddr, bytes data) {
    require forall mathint a. forall mathint b. forall mathint d. axiomDownLowerBound(a, b, d), "floor lower bound on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomDownStrictness(a, b, d), "floor strictness on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomUpUpperBound(a, b, d), "ceil upper bound on mulDivUp";

    // Pin the market to concrete values via the globalMarket* ghosts; equalsGlobalMarket
    // then matches a Market with these fields, and summaryToId returns globalId.
    require globalMarketLoanToken == 0x0000000000000000000000000000000000001001;
    require globalMarketCollateralLength == 1;
    require globalMarketCollateralOracle[0] == 0x0000000000000000000000000000000000001003;
    require globalMarketCollateralToken[0] == 0x0000000000000000000000000000000000001002;
    require globalMarketCollateralLLTV[0] == 770000000000000000;          // 0.77 * WAD
    require globalMarketCollateralMaxLif[0] == 1061007957559681697;       // ~1.061 * WAD
    require globalMarketMaturity == 2000000000;
    require globalMarketRcfThreshold == 0;
    require globalMarketEnterGate == 0;
    require globalMarketLiquidatorGate == 0;

    Midnight.Market globalMarket = getGlobalMarket();

    uint256 lltv = globalMarketCollateralLLTV[0];
    uint256 maxLif = globalMarketCollateralMaxLif[0];
    uint256 lifTimesLltv = summaryMulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "maxLif * lltv < 1 so the RCF denominator (1 - maxLif * lltv) is positive";

    uint256 price = summaryPrice(globalMarketCollateralOracle[0]);
    uint256 collatBefore = collateral(globalId, globalBorrower, 0);
    uint256 debtBefore = debtOf(globalId, globalBorrower);

    require collatBefore > 0, "borrower has collateral to seize";
    require e.block.timestamp < globalMarketMaturity, "ensure RCF condition is activated";

    uint256 maxDebt = summaryMulDivDown(summaryMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    require debtBefore > maxDebt, "position is unhealthy before liquidation";

    uint256 rcfCap = summaryMulDivUp(assert_uint256(debtBefore - maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    uint256 actualSeized;
    uint256 actualRepaid;

    actualSeized, actualRepaid = liquidate(e, globalMarket, 0, seizedAssets, repaidUnits, globalBorrower, receiver, callbackAddr, data);

    require actualRepaid == rcfCap, "max allowed to be repaid by RCF condition is repaid";
    assert isHealthyNoBitmap(globalMarket, globalId, globalBorrower);
}

// Single-collateral variant of healthyAfterMaxRcfLiquidation: pins
// globalMarketCollateralLength == 1 so the only valid collateralIndex is 0.
rule healthyAfterMaxRcfLiquidationSingleCollateral(env e, uint256 seizedAssets, uint256 repaidUnits, address receiver, address callbackAddr, bytes data) {
    require forall mathint a. forall mathint b. forall mathint d. axiomDownLowerBound(a, b, d), "floor lower bound on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomDownStrictness(a, b, d), "floor strictness on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomUpUpperBound(a, b, d), "ceil upper bound on mulDivUp";

    require globalMarketCollateralLength == 1, "single collateral asset";

    Midnight.Market globalMarket = getGlobalMarket();

    uint256 lltv = globalMarketCollateralLLTV[0];
    uint256 maxLif = globalMarketCollateralMaxLif[0];
    require maxLif >= WAD(), "maxLif is at least 1";
    uint256 lifTimesLltv = summaryMulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "maxLif * lltv < 1 so the RCF denominator (1 - maxLif * lltv) is positive";

    uint256 price = summaryPrice(globalMarketCollateralOracle[0]);
    uint256 collatBefore = collateral(globalId, globalBorrower, 0);
    uint256 debtBefore = debtOf(globalId, globalBorrower);

    require collatBefore > 0, "borrower has collateral to seize";
    require e.block.timestamp < globalMarketMaturity, "ensure RCF condition is activated";

    uint256 maxDebt = summaryMulDivDown(summaryMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    require debtBefore > maxDebt, "position is unhealthy before liquidation";

    uint256 rcfCap = summaryMulDivUp(assert_uint256(debtBefore - maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    uint256 actualSeized;
    uint256 actualRepaid;

    actualSeized, actualRepaid = liquidate(e, globalMarket, 0, seizedAssets, repaidUnits, globalBorrower, receiver, callbackAddr, data);

    require actualRepaid == rcfCap, "max allowed to be repaid by RCF condition is repaid";
    assert isHealthyNoBitmap(globalMarket, globalId, globalBorrower);
}

// Show that a liquidation repaying the maximum amount allowed by the RCF condition
// leaves the position healthy. The market is bound to the global ghosts via
// getGlobalMarket(), so storage keys come from globalId.
rule healthyAfterMaxRcfLiquidation(env e, uint256 seizedAssets, uint256 repaidUnits, address receiver, address callbackAddr, bytes data) {
    require forall mathint a. forall mathint b. forall mathint d. axiomDownLowerBound(a, b, d), "floor lower bound on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomDownStrictness(a, b, d), "floor strictness on mulDivDown";
    require forall mathint a. forall mathint b. forall mathint d. axiomUpUpperBound(a, b, d), "ceil upper bound on mulDivUp";

    require globalMarketCollateralLength <= 2, "too many collateralParams for the spec to handle";

    uint256 collateralIndex;
    require collateralIndex < globalMarketCollateralLength, "invalid collateral index";

    Midnight.Market globalMarket = getGlobalMarket();

    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 maxLif = globalMarketCollateralMaxLif[collateralIndex];
    require maxLif >= WAD(), "maxLif is at least 1";
    uint256 lifTimesLltv = summaryMulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "maxLif * lltv < 1 so the RCF denominator (1 - maxLif * lltv) is positive";

    uint256 price = summaryPrice(globalMarketCollateralOracle[collateralIndex]);
    uint256 collatBefore = collateral(globalId, globalBorrower, collateralIndex);
    uint256 debtBefore = debtOf(globalId, globalBorrower);

    require collatBefore > 0, "borrower has collateral to seize";
    require e.block.timestamp < globalMarketMaturity, "ensure RCF condition is activated";

    uint256 maxDebt = summaryMulDivDown(summaryMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    require debtBefore > maxDebt, "position is unhealthy before liquidation";

    uint256 actualSeized;
    uint256 actualRepaid;

    actualSeized, actualRepaid = liquidate(e, globalMarket, collateralIndex, seizedAssets, repaidUnits, globalBorrower, receiver, callbackAddr, data);

    require actualRepaid == summaryMulDivUp(assert_uint256(debtBefore - maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv)), "actualRepaid equals the RCF cap = (debt - maxDebt) / (1 - maxLif * lltv)";

    assert isHealthyNoBitmap(globalMarket, globalId, globalBorrower);
}
