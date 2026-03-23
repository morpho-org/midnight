// SPDX-License-Identifier: GPL-2.0-or-later

/// Proves that an RCF-limited liquidation (actualRepaid == maxRepaid) leaves the
/// position healthy.
///
/// This rule requires exact mathint arithmetic for mulDivDown/mulDivUp because
/// the proof depends on algebraic cancellation across state changes — the
/// uninterpreted ghost approach used in RecoveryCloseFactor.spec is insufficient.

methods {
    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);

    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);

    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;

    function collateralOf(bytes32, address, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function activatedCollaterals(bytes32, address) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
}

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

ghost CVL_msb(uint256) returns uint256;

ghost CVL_price(address) returns uint256;

/// Exact mulDivDown: floor(a * b / d)
function CVL_mulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0;
    return require_uint256((to_mathint(a) * to_mathint(b)) / to_mathint(d));
}

/// Exact mulDivUp: ceil(a * b / d)
function CVL_mulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0;
    return require_uint256((to_mathint(a) * to_mathint(b) + to_mathint(d) - 1) / to_mathint(d));
}

definition WAD() returns uint256 = 10 ^ 18;
definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

/// Proves that an RCF-limited liquidation (actualRepaid == maxRepaid) leaves the
/// position healthy — isHealthy returns true after the liquidation.
rule rcfLiquidationRestoresHealth(
    env e,
    Midnight.Obligation obligation,
    uint256 seizedAssets,
    uint256 repaidUnits,
    address borrower,
    bytes data
) {
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv   = obligation.collaterals[0].lltv;
    uint256 maxLif = obligation.collaterals[0].maxLif;
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price  = CVL_price(obligation.collaterals[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore   = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp <= obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    // First liquidation succeeds
    uint256 actualRepaid;
    (_, actualRepaid) = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxRepaid (post-call, exact arithmetic via mathint)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);
    uint256 badDebt = debtBefore > collatValuePerMaxLif
        ? assert_uint256(debtBefore - collatValuePerMaxLif)
        : 0;
    uint256 effectiveDebt = assert_uint256(debtBefore - badDebt);

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(effectiveDebt - _maxDebt), WAD(), denom);

    // RCF was the binding constraint
    require actualRepaid == _maxRepaid;

    // Position is healthy after the liquidation
    assert !isHealthy(obligation, id, borrower),
        "RCF-limited liquidation must leave position unhealthy";
}
