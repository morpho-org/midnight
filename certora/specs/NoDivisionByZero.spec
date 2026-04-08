// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that no division by zero occurs in mulDivDown or mulDivUp.
//
// All other Solidity divisions in the codebase use constant denominators:
// - tradingFee: divides by (end - start), always a positive constant from the breakpoint table.
// - setObligationTradingFee / setDefaultTradingFee: divide by FEE_STEP (1e12).
// - liquidate: divides by TIME_TO_MAX_LIF (15 minutes = 900).
// Therefore, only mulDivDown and mulDivUp can have variable denominators.
//
// maxLif(uint256, uint256) is excluded: it is a pure function callable with arbitrary inputs.
// A standalone call with cursor >= WAD causes a safe revert (Solidity checked arithmetic).
//
// The liquidate function is verified in a separate rule (noDivisionByZeroLiquidate).
// The toId summary follows the approach from PR #388: a ghost-backed deterministic function.

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => ghostPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation, chainId, midnight);

    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// GHOSTS ///

persistent ghost bool divisionByZero {
    init_state axiom !divisionByZero;
}

// Global obligation ghosts for deterministic toId (approach from PR #388).
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

/// HOOKS ///

// lossIndex < max: the protocol stop behaving correctly if this happens (documented).
hook Sload uint128 value obligationState[KEY bytes32 id].lossIndex {
    require value < max_uint128;
}

// Follows from userLossIndexLeqObligationLossIndex in Midnight.spec and the hook above.
hook Sload uint128 value position[KEY bytes32 id][KEY address user].lossIndex {
    require value < max_uint128;
}

/// SUMMARIES ///

ghost ghostPrice(address) returns uint256;

definition WAD() returns uint256 = 1000000000000000000;

definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool = (index < globalObligationCollateralLength => obligation.collateralParams[index].oracle == globalObligationCollateralOracle[index] && obligation.collateralParams[index].token == globalObligationCollateralToken[index] && obligation.collateralParams[index].lltv == globalObligationCollateralLLTV[index] && obligation.collateralParams[index].maxLif == globalObligationCollateralMaxLif[index]);

function equalsGlobalObligation(Midnight.Obligation obligation) returns (bool) {
    return obligation.loanToken == globalObligationLoanToken && obligation.collateralParams.length == globalObligationCollateralLength && collateralMatches(obligation, 0) && collateralMatches(obligation, 1) && collateralMatches(obligation, 2) && obligation.maturity == globalObligationMaturity && obligation.rcfThreshold == globalObligationRcfThreshold && obligation.enterGate == globalObligationEnterGate && obligation.liquidatorGate == globalObligationLiquidatorGate;
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

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        divisionByZero = true;
    }
    uint256 result;
    require d == 0 || to_mathint(result) * to_mathint(d) <= to_mathint(x) * to_mathint(y);
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;
    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        divisionByZero = true;
    }
    uint256 result;
    require d == 0 || to_mathint(result) * to_mathint(d) <= to_mathint(x) * to_mathint(y) + to_mathint(d) - 1;
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;
    return result;
}

/// RULES ///

rule noDivisionByZero(method f, env e, calldataarg args) filtered { f -> f.selector != sig:maxLif(uint256, uint256).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    require !divisionByZero;
    f(e, args);
    assert !divisionByZero, "division by zero detected in mulDivDown or mulDivUp";
}

rule noDivisionByZeroLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require equalsGlobalObligation(obligation);

    // Sound: touchObligation enforces maxLif >= WAD for all collateralParams (ExactMath.spec).
    // Needed for the bitmap loop which calls mulDivUp(WAD, maxLif) for every activated collateral.
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].maxLif >= WAD();

    // Sound: ExactMath.spec proves maxLif * lltv <= WAD * (WAD - 1) when lltv < WAD (lifTimesLltvStrictBound).
    require obligation.collateralParams[collateralIndex].lltv < WAD() => to_mathint(obligation.collateralParams[collateralIndex].maxLif) * to_mathint(obligation.collateralParams[collateralIndex].lltv) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "see lifTimesLltvStrictBound in ExactMath.spec";

    // Assume that the collateral price is non-zero and the collateral is active. Otherwise, liquidate may revert with div by zero.
    require ghostPrice(obligation.collateralParams[collateralIndex].oracle) > 0, "Assumption: the collateral price is not zero";
    require summaryGetBit(currentContract.position[globalId][borrower].activatedCollaterals, collateralIndex), "Assumption: liquidated collateral was activated";

    require !divisionByZero;
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert !divisionByZero, "division by zero detected in mulDivDown or mulDivUp";
}
