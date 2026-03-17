// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Summarize mulDivDown and mulDivUp by ghost functions for prover performance.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryMulDivDownM(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (summaryMulDivDownM(a, b, d) + 1) * d > a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDownM(a, b, d) * d <= a * b;
}

persistent ghost summaryMulDivUpM(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => summaryMulDivUpM(a, b, d) * d < a * b + d;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => summaryMulDivUpM(a, b, d) * d >= a * b;
}

// Non-deterministic overflow models potential revert on x * y overflow.
function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return summaryMulDivDownM(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return summaryMulDivUpM(a, b, d);
}

/// LIQUIDATION PROFITABILITY ///

/// Liquidation is profitable up 1 collateral token unit in price-scaled terms due to floor rounding
rule liquidationIsProfitableRepaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD(), "maxLif must be at least 1x for profitability";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert repaidUnits > 0 => (seizedResult + 1) * price > repaidResult * ORACLE_PRICE_SCALE();
}

/// Liquidation is profitable up to 1 loan token unit due to ceil rounding
rule liquidationIsProfitableSeizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD(), "maxLif must be at least 1x for profitability";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert seizedAssets > 0 => seizedResult * price > (repaidResult - 1) * ORACLE_PRICE_SCALE();
}
