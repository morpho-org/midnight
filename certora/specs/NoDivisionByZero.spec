// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that no division by zero occurs in mulDivDown or mulDivUp.
//
// All other Solidity divisions in the codebase use non-zero denominators:
// - tradingFee: divides by (end - start), always a positive constant from the breakpoint table.
// - setMarketTradingFee / setDefaultTradingFee: divide by CBP (1e12).
// - liquidate: divides by TIME_TO_MAX_LIF (15 minutes = 900).
// - tickToPrice: divides by 5e12 or a value greater than 1e18.
// - wExp, used in tickToPrice: divides by non-zero constants.
// Therefore, we only look for division by zero in mulDivDown and mulDivUp in this file.

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Ghost price function so that the price can be referenced in the rules.
    function _.price() external => ghostPrice(calledContract) expect(uint256);

    // Summary for deterministic toId for the global market.
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market, chainId, midnight);

    // This function is checked manually to not cause a division by zero.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Hook on mulDivDown and mulDivUp to check that the denominator is not zero, and add the necessary lemmas.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// GHOSTS ///

// Reuse part of the setup of Healthiness.spec.

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

/// HOOKS ///

// Follows from lastLossFactorLeqMarketLossFactor in Midnight.spec.
hook Sload uint128 value position[KEY bytes32 id][KEY address user].lastLossFactor {
    require value <= currentContract.marketState[id].lossFactor;
}

/// SUMMARIES ///

ghost ghostPrice(address) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

definition collateralMatches(Midnight.Market market, uint256 index) returns bool = (index < globalMarketCollateralLength => market.collateralParams[index].oracle == globalMarketCollateralOracle[index] && market.collateralParams[index].token == globalMarketCollateralToken[index] && market.collateralParams[index].lltv == globalMarketCollateralLLTV[index] && market.collateralParams[index].maxLif == globalMarketCollateralMaxLif[index]);

function equalsGlobalMarket(Midnight.Market market) returns (bool) {
    return market.loanToken == globalMarketLoanToken && market.collateralParams.length == globalMarketCollateralLength && collateralMatches(market, 0) && collateralMatches(market, 1) && collateralMatches(market, 2) && market.maturity == globalMarketMaturity && market.rcfThreshold == globalMarketRcfThreshold && market.enterGate == globalMarketEnterGate && market.liquidatorGate == globalMarketLiquidatorGate;
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

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    assert d > 0;

    uint256 result;
    require y <= d => result <= x, "see mulDivArgumentLesserThanDenominator in MulDiv.spec";
    require x <= d => result <= y, "see mulDivArgumentLesserThanDenominator in MulDiv.spec";
    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    assert d > 0;

    uint256 result;
    require result * d <= x * y + d - 1, "see mulDivUpUpperBound in MulDiv.spec";
    require y <= d => result <= x, "see mulDivArgumentLesserThanDenominator in MulDiv.spec";
    require x <= d => result <= y, "see mulDivArgumentLesserThanDenominator in MulDiv.spec";
    return result;
}

/// RULES ///

// The liquidate function is verified in a separate rule (noDivisionByZeroLiquidate).
rule noDivisionByZero(method f, env e, calldataarg args) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector } {
    f(e, args);
    assert true;
}

// Show that liquidate does not cause a division by zero, in case the oracle price is non-zero and the collateral is active.
rule noDivisionByZeroLiquidate(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require equalsGlobalMarket(market);

    // Needed for the bitmap loop which calls mulDivUp(WAD, maxLif) for every activated collateral.
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].maxLif >= WAD(), "see maxLifIsAtLeastWad in ExactMath.spec";

    require market.collateralParams[collateralIndex].lltv < WAD() => to_mathint(market.collateralParams[collateralIndex].maxLif) * to_mathint(market.collateralParams[collateralIndex].lltv) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "see lifTimesLltvStrictBound in ExactMath.spec";

    // Assume that the collateral price is non-zero and the collateral is active. Otherwise, liquidate may revert with div by zero.
    require ghostPrice(market.collateralParams[collateralIndex].oracle) > 0, "Assumption: the collateral price is not zero";
    require summaryGetBit(currentContract.position[globalId][borrower].collateralBitmap, collateralIndex), "Assumption: liquidated collateral was activated";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert true;
}
