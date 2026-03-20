// SPDX-License-Identifier: GPL-2.0-or-later

/// Proves that when rcfThreshold = 0, the Recovery Close Factor bound
/// `repaidUnits <= maxRepaid` is always enforced on pre-maturity liquidations.
/// Assumes: single-collateral obligations (collaterals.length == 1), seizedAssets == 0.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight)
        internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);

    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d)
        internal returns (uint256) => CVL_mulDivDown(a, b, d);

    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d)
        internal returns (uint256) => CVL_mulDivUp(a, b, d);

    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;

    function collateralOf(bytes32, address, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function activatedCollaterals(bytes32, address) external returns (uint128) envfree;
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
    address oracle = obligation.collaterals[0].oracle;
    uint256 price  = CVL_price(oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore   = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    // Mirror maxDebt: collatOf.mulDivDown(price, OPS).mulDivDown(lltv, WAD)
    uint256 innerDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(innerDown, lltv, WAD());

    require to_mathint(debtBefore) > to_mathint(_maxDebt);

    // Mirror bad-debt deduction
    uint256 innerUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(innerUp, WAD(), maxLif);
    uint256 badDebt = debtBefore > collatValuePerMaxLif
        ? require_uint256(to_mathint(debtBefore) - to_mathint(collatValuePerMaxLif))
        : 0;
    uint256 effectiveDebt = require_uint256(to_mathint(debtBefore) - to_mathint(badDebt));

    require to_mathint(effectiveDebt) >= to_mathint(_maxDebt);

    // Mirror maxRepaid: (effectiveDebt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
    // lif = maxLif because originalDebt > maxDebt
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require to_mathint(lifTimesLltv) < to_mathint(WAD());
    uint256 denom = require_uint256(to_mathint(WAD()) - to_mathint(lifTimesLltv));
    uint256 maxRepaidArg = require_uint256(to_mathint(effectiveDebt) - to_mathint(_maxDebt));
    uint256 _maxRepaid = CVL_mulDivUp(maxRepaidArg, WAD(), denom);

    require obligation.rcfThreshold == 0;
    require e.block.timestamp <= obligation.maturity;
    require seizedAssets == 0;
    require repaidUnits > 0;

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    assert repaidUnits <= _maxRepaid,
        "rcfThreshold=0 must enforce repaidUnits <= maxRepaid on all pre-maturity liquidations";
}
