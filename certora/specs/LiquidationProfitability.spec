// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns mathint = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a, b, d) >= 0;

    /* floor bound: (floor(a*b/d) + 1) * d > a*b -- proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => (summaryMulDivDownM(a, b, d) + 1) * d > a * b;

    /* floor upper bound: floor(a*b/d) * d <= a*b -- proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a, b, d) * d <= a * b;

    /* floor ratio: floor(a*b/d) >= a when b >= d -- in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= d && d > 0 => summaryMulDivDownM(a, b, d) >= a;
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) >= 0;

    /* ceil upper bound: ceil(a*b/d) * d < a*b + d -- proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) * d < a * b + d;

    /* ceil lower bound: ceil(a*b/d) * d >= a*b -- proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) * d >= a * b;

    /* ceil ratio: ceil(a*b/d) <= a when 0 < b <= d -- proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && 0 < b && b <= d => summaryMulDivUpM(a, b, d) <= a;
}

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

/// Liquidation is profitable up to floor rounding (repaidUnits input)
rule liquidationIsProfitable_repaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD();
    require repaidUnits > 0;

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert (to_mathint(seizedResult) + 1) * price > to_mathint(repaidResult) * ORACLE_PRICE_SCALE();
}

/// Liquidation is profitable up to ceil rounding (seizedAssets input)
rule liquidationIsProfitable_seizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD();
    require seizedAssets > 0;

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price + ORACLE_PRICE_SCALE() > to_mathint(repaidResult) * ORACLE_PRICE_SCALE();
}

/// Liquidation profit is bounded by maxLif (repaidUnits input)
rule liquidationProfitBounded_repaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require maxLif >= WAD();
    require repaidUnits > 0;

    // reduce callback path exploration
    require data.length == 0;

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBounded_seizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require maxLif >= WAD();
    require seizedAssets > 0;

    // reduce callback path exploration
    require data.length == 0;

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    require repaidResult > 0;

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}
