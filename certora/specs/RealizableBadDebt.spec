// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";
import "MulDivAxioms.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function totalUnits(bytes32) external returns (uint128) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Safe because the protocol doesn't use `toMarket`
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Over-approximate the following functions.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // All external calls are assumed non-reentrant / non-reverting: we reason about the function bodies for safety properties.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
}

/// HELPERS

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost summaryPrice(address) returns uint256;

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

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// PROPERTIES

// No non-liquidate function may increase realizableBadDebt of a position.
rule realizableBadDebtCannotIncrease(env e, method f, calldataarg args, Midnight.Market market, address borrower) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    bytes32 id = summaryToId(market);

    // If seller is locked, they can create a position with bad debt.
    // In that case the position must be healthy when the lock is removed later and no bad debt can be realized.
    require !liquidationLocked(id, borrower), "scope out the re-entrant case";

    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomMathMulDivUpMonotoneA(a1, a2, b, d), "axiom";
    require forall mathint a. forall mathint b. forall mathint d. axiomMathMulDivUpGeqMulDivDown(a, b, d), "axiom";
    require forall mathint a. forall mathint lltv. forall mathint lif. axiomMathMulDivUpMonotoneBD(a, lltv, WAD(), WAD(), lif), "axiom";

    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "see createdMarketsHaveEnabledLltv in CreatedMarkets.spec and enabledLltvIsLessThanOrEqualToOne in Midnight.spec";
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].liquidationCursor < WAD(), "see createdMarketsHaveEnabledLiquidationCursor in CreatedMarkets.spec and enabledLiquidationCursorsIsLessThanOne in Midnight.spec";
    require forall uint256 lltv. forall uint256 cursor. lltv <= WAD() && cursor < WAD() => lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "see lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";

    uint256 badDebtBefore = realizableBadDebt(market, id, borrower);

    f(e, args);

    uint256 badDebtAfter = realizableBadDebt(market, id, borrower);

    assert badDebtAfter <= badDebtBefore;
}

// liquidate drops totalUnits by exactly the realized bad debt.
rule liquidateRealizesTotalUnits(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require debt(id, borrower) <= totalUnits(id), "proven by totalUnitsEqualsSumNegativeDebtPlusWithdrawable";

    uint256 badDebtBefore = realizableBadDebt(market, id, borrower);
    uint256 totalUnitsBefore = totalUnits(id);
    assert badDebtBefore <= totalUnitsBefore;

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert totalUnits(id) == totalUnitsBefore - badDebtBefore;
}

// A healthy position has no realizable bad debt, so liquidating it cannot write off any debt.
// Together with notLiquidatableWhenLocked (Healthiness.spec) and the strong invariant isHealthy || liquidationLocked, this shows that liquidate() never writes off debt of a position that was healthy at the start of the transaction, even from inside a callback.
rule healthyHasNoRealizableBadDebt(Midnight.Market market, address borrower) {
    bytes32 id = summaryToId(market);

    // For one collateral, write c: collateral, p:price, S:ORACLE_PRICE_SCALE, down:mulDivDown, up:mulDivUp.
    // Hint to the prover: down(down(c, p, S), lltv, WAD) <= down(up(c, p, S), lltv, WAD) <= up(up(c, p, S), lltv, WAD) <= up(up(c, p, S), WAD, maxLif).
    require forall mathint c. forall mathint p. axiomMathMulDivUpGeqMulDivDown(c, p, ORACLE_PRICE_SCALE()), "axiom";
    require forall mathint c. forall mathint p. forall mathint lltv. axiomMathMulDivDownMonotoneA(mathMulDivDown(c, p, ORACLE_PRICE_SCALE()), mathMulDivUp(c, p, ORACLE_PRICE_SCALE()), lltv, WAD()), "axiom";
    require forall mathint c. forall mathint p. forall mathint lltv. axiomMathMulDivUpGeqMulDivDown(mathMulDivUp(c, p, ORACLE_PRICE_SCALE()), lltv, WAD()), "axiom";
    require forall mathint c. forall mathint p. forall mathint lltv. forall mathint lif. axiomMathMulDivUpMonotoneBD(mathMulDivUp(c, p, ORACLE_PRICE_SCALE()), lltv, WAD(), WAD(), lif), "axiom";

    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "see createdMarketsHaveEnabledLltv in CreatedMarkets.spec and enabledLltvIsLessThanOrEqualToOne in Midnight.spec";
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].liquidationCursor < WAD(), "see createdMarketsHaveEnabledLiquidationCursor in CreatedMarkets.spec and enabledLiquidationCursorsIsLessThanOne in Midnight.spec";
    require forall uint256 lltv. forall uint256 cursor. lltv <= WAD() && cursor < WAD() => lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "see lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";

    require isHealthy(market, id, borrower), "borrower is healthy";

    assert realizableBadDebt(market, id, borrower) == 0;
}
