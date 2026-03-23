// SPDX-License-Identifier: GPL-2.0-or-later

/// Rule 1: Proves that when rcfThreshold = 0, the Recovery Close Factor bound
/// `repaidUnits <= maxRepaid` is always enforced on pre-maturity liquidations.
///
/// Rule 2: Proves that when rcfThreshold = max_uint256, the RCF check is effectively
/// disabled — the second disjunct of the require is always true, so repaidUnits
/// is not constrained by maxRepaid.

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

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;
definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

rule zeroRcfThresholdAlwaysEnforcesRcf(
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
    require maxLif >= WAD();
    uint256 price  = CVL_price(obligation.collaterals[0].oracle);

    // Read pre-call state via view functions
    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore   = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require obligation.rcfThreshold == 0;
    require e.block.timestamp <= obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    // Call liquidate — non-reverting paths only.
    // After this, the solver knows the ghosts are consistent with a successful execution.
    uint256 actualRepaid;
    (_, actualRepaid) = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxDebt (computed after the call — ghosts are persistent,
    // and the non-reverting call constrains them to valid values)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    // Mirror bad-debt deduction
    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);
    uint256 badDebt = debtBefore > collatValuePerMaxLif
        ? assert_uint256(debtBefore - collatValuePerMaxLif)
        : 0;
    uint256 effectiveDebt = assert_uint256(debtBefore - badDebt);

    // Mirror maxRepaid: (effectiveDebt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
    // lif = maxLif because originalDebt > maxDebt (enforced by Solidity line 394)
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(effectiveDebt - _maxDebt), WAD(), denom);

    assert actualRepaid <= _maxRepaid,
        "rcfThreshold=0 must enforce repaidUnits <= maxRepaid on all pre-maturity liquidations";
}

/// Shows that when rcfThreshold = max_uint256, a liquidation with repaidUnits
/// exceeding maxRepaid CAN succeed — the RCF check does not block it.
rule maxRcfThresholdNeverEnforcesRcf(
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
    require maxLif >= WAD();
    uint256 price  = CVL_price(obligation.collaterals[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore   = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require obligation.rcfThreshold == max_uint256;
    require e.block.timestamp <= obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    uint256 actualRepaid;
    (_, actualRepaid) = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxRepaid (after the call — ghosts constrained by non-reverting execution)
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

    satisfy actualRepaid > _maxRepaid;
}

/// Proves the full RCF condition for any rcfThreshold: on all non-reverting
/// pre-maturity liquidations, the Solidity require at line 428 holds:
///   repaidUnits <= maxRepaid || collateralValue.zeroFloorSub(maxRepaid) < rcfThreshold
rule rcfConditionAlwaysHolds(
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
    require maxLif >= WAD();
    uint256 price  = CVL_price(obligation.collaterals[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore   = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp <= obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    uint256 actualRepaid;
    (_, actualRepaid) = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxRepaid (after the call — ghosts constrained by non-reverting execution)
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

    // Mirror second disjunct: collateral.mulDivDown(price, OPS).mulDivDown(WAD, lif).zeroFloorSub(maxRepaid)
    // Uses collatBefore (line 430 reads pre-seizure collateral)
    // lif = maxLif (because originalDebt > maxDebt when timestamp <= maturity)
    uint256 collatValueForRcf = CVL_mulDivDown(CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    mathint rcfValue = collatValueForRcf > _maxRepaid
        ? collatValueForRcf - _maxRepaid
        : 0;

    assert actualRepaid <= _maxRepaid || rcfValue < obligation.rcfThreshold,
        "RCF conditions must hold on all pre-maturity liquidations";
}
