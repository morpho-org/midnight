// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    // envfree declarations
    function collateralOf(bytes32, address, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function activatedCollaterals(bytes32, address) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);
    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    // Summaries for external calls.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
}

// IdLib summary: remember the last id returned by toId.

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    // non-deterministic id
    bytes32 id;
    lastId = id;
    return id;
}

// UtilsLib summaries: msb, mulDivDown, and mulDivUp are deterministic

ghost CVL_msb(uint256) returns uint256;

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

// Oracle summary: we assume the price does not change during the execution of a transaction.

ghost CVL_price(address) returns uint256;

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// For any rcfThreshold, the RCF condition holds on all non-reverting pre-maturity liquidations:
// repaidUnits <= maxRepaid || collateralValue.zeroFloorSub(maxRepaid) < rcfThreshold.
// As a special, shows that RCF is always active pre-maturity if rcfThreshold is zero.
// Proven for obligations with a single collateral.
rule liquidationRespectsRcfBound(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1, "we assume single collateral obligations";
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[0].lltv;
    uint256 maxLif = obligation.collaterals[0].maxLif;
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";

    uint256 price = CVL_price(obligation.collaterals[0].oracle);

    // Read pre-call state via getters
    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    // call setup
    require collatBefore > 0, "call setup";
    require activatedCollaterals(id, borrower) == 1, "call setup";
    require CVL_msb(1) == 0, "call setup";
    require seizedAssets > 0 || repaidUnits > 0, "call setup";

    require e.block.timestamp <= obligation.maturity, "assume liquidation pre-maturity";

    // liquidate called.
    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // it's okay to check only after the call that the prover chose the correct id.
    require id == lastId, "id should be derived from obligation";

    // Mirror maxDebt (computed after the call — ghosts are persistent, and the non-reverting call constrains them to valid values)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    // Mirror bad-debt deduction
    uint256 collatValue = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 maxSupportedDebt = CVL_mulDivUp(collatValue, WAD(), maxLif);
    uint256 badDebt = debtBefore > maxSupportedDebt ? assert_uint256(debtBefore - maxSupportedDebt) : 0;
    uint256 effectiveDebt = assert_uint256(debtBefore - badDebt);

    // Mirror maxRepaid: (effectiveDebt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(effectiveDebt - _maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    // // Mirror rcfValue computation
    uint256 maxSupportedDebt = CVL_mulDivDown(CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);
    uint256 rcfValue = maxSupportedDebt > _maxRepaid ? assert_uint256(maxSupportedDebt - _maxRepaid) : 0;

    assert actualRepaid <= _maxRepaid || rcfValue < obligation.rcfThreshold, "RCF conditions must hold on all pre-maturity liquidations";

    //special case: if rcfThreshold is zero then RCF is always activated.
    assert obligation.rcfThreshold != 0 || actualRepaid <= _maxRepaid, "rcfThreshold=0 must enforce repaidUnits <= maxRepaid on all pre-maturity liquidations";
}

// If rcfThreshold = max_uint256, then repaying more than the RCF condition is always possible.
// Proven for obligations with single collateral.
rule maxRcfThresholdNeverEnforcesRcf(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1, "we assume single collateral obligations";
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[0].lltv;
    uint256 maxLif = obligation.collaterals[0].maxLif;
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";

    uint256 price = CVL_price(obligation.collaterals[0].oracle);

    // Read pre-call state via getters
    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    // Call setup
    require collatBefore > 0, "call setup";
    require activatedCollaterals(id, borrower) == 1, "call setup";
    require CVL_msb(1) == 0, "call setup";
    require seizedAssets > 0 || repaidUnits > 0, "call setup";

    require obligation.rcfThreshold == max_uint256, "assume rcfThreshold is MAX UINT256";
    require e.block.timestamp <= obligation.maturity, "assume liquidation pre-maturity";

    // Liquidate called.
    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // It's okay to check only after the call that the prover chose the correct id.
    require id == lastId, "id should be derived from obligation";

    // Mirror maxDebt (computed after the call — ghosts are persistent, and the non-reverting call constrains them to valid values)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    // Mirror bad-debt deduction
    uint256 collatValue = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 maxSupportedDebt = CVL_mulDivUp(collatValue, WAD(), maxLif);
    uint256 badDebt = debtBefore > maxSupportedDebt ? assert_uint256(debtBefore - maxSupportedDebt) : 0;
    uint256 effectiveDebt = assert_uint256(debtBefore - badDebt);

    // Mirror maxRepaid: (effectiveDebt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(effectiveDebt - _maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    satisfy actualRepaid > _maxRepaid, "if rcfThreshold is max_uint256, RCF is not enforced";
}
