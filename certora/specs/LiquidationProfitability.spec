// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation, chainId, midnight);
    function IdLib.storeInCode(Midnight.Obligation memory obligation) internal returns (address) => NONDET;
    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => summaryMsb(bitmap);
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// ASSUMPTIONS ///

// price does not change during a transaction.
// mulDivDown/Up() fulfill the axioms defined here (the base axioms are proved in MulDiv.spec).
// The floor bound, ceil upper bound, floor ratio, and ceil ratio axioms should also be proved in MulDiv.spec.

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;
definition ORACLE_PRICE_SCALE() returns mathint = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    return id;
}

ghost summaryMsb(uint256) returns uint256;

persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a, b, d) >= 0;

    /* proved in mulDivZero in MulDiv.spec */
    axiom forall mathint b. forall mathint d. d > 0 => summaryMulDivDownM(0, b, d) == 0;

    /* proved in mulDivMonotoneA in MulDiv.spec */
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 => summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);

    /* proved in mulDivMonotoneB in MulDiv.spec */
    axiom forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. d > 0 && b1 <= b2 => summaryMulDivDownM(a, b1, d) <= summaryMulDivDownM(a, b2, d);

    /* floor bound: (floor(a*b/d) + 1) * d > a*b -- should be proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => (summaryMulDivDownM(a, b, d) + 1) * d > a * b;

    /* floor ratio: floor(a*b/d) >= a when b >= d -- should be proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= d && d > 0 => summaryMulDivDownM(a, b, d) >= a;
}

persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint {
    /* mulDiv always returns an unsigned integer */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) >= 0;

    /* proved in mulDivMonotoneA in MulDiv.spec */
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 => summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);

    /* proved in mulDivMonotoneD in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. d1 > 0 && d1 <= d2 => summaryMulDivUpM(a, b, d1) >= summaryMulDivUpM(a, b, d2);

    /* ceil upper bound: ceil(a*b/d) * d < a*b + d -- should be proved in MulDiv.spec */
    axiom forall mathint a. forall mathint b. forall mathint d. a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) * d < a * b + d;

    /* ceil ratio: ceil(a*b/d) <= a when 0 < b <= d -- should be proved in MulDiv.spec */
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

/// RULES ///

/// Liquidation is profitable (repaidUnits input):
/// seized >= floor(repaid * ORACLE_PRICE_SCALE / price), i.e. at most 1 collateral unit lost to rounding.
rule liquidationIsProfitable_repaidUnits(
    env e,
    Midnight.Obligation obligation,
    uint256 collateralIndex,
    uint256 repaidUnits,
    address borrower,
    bytes data
) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD();
    require obligation.collaterals[collateralIndex].lltv <= WAD();
    require repaidUnits > 0;
    require data.length == 0;

    uint256 seizedResult;
    uint256 repaidResult;
    (seizedResult, repaidResult) = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert (to_mathint(seizedResult) + 1) * price > to_mathint(repaidResult) * ORACLE_PRICE_SCALE(), "repaidUnits case: profitable up to floor rounding";
}

/// Liquidation is profitable (seizedAssets input):
/// repaid <= ceil(seized * price / ORACLE_PRICE_SCALE), i.e. at most 1 loan unit extra due to rounding.
rule liquidationIsProfitable_seizedAssets(
    env e,
    Midnight.Obligation obligation,
    uint256 collateralIndex,
    uint256 seizedAssets,
    address borrower,
    bytes data
) {
    require obligation.collaterals[collateralIndex].maxLif >= WAD();
    require obligation.collaterals[collateralIndex].lltv <= WAD();
    require seizedAssets > 0;
    require data.length == 0;

    uint256 seizedResult;
    uint256 repaidResult;
    (seizedResult, repaidResult) = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price + ORACLE_PRICE_SCALE() > to_mathint(repaidResult) * ORACLE_PRICE_SCALE(), "seizedAssets case: profitable up to ceil rounding";
}
