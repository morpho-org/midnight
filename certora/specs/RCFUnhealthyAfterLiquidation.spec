// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that an RCF-limited liquidation (actualRepaid == maxRepaid) makes the
// position at most "slightly healthy": the exact maxDebt exceeds the new debt by
// at most 1 unit. This accounts for the mulDivUp rounding in maxRepaid, which
// the contract acknowledges at Midnight.sol L494-495.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);

    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

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
/// position at most "slightly healthy": the exact maxDebt exceeds the new debt
/// by at most 3 unit.
///
/// The mulDivUp rounding in maxRepaid (Midnight.sol L494-497) intentionally
/// overshoots by up to ε * denom / WAD < 1 debt unit in continuous math.
/// The contract acknowledges this: "the position could be slightly healthy
/// after a liquidation."
///
/// Preconditions exclude cases where the RCF is structurally deactivated:
///   - badDebt > 0:        debt is reduced before the RCF check runs
///   - maxRepaid >= debt:  RCF imposes no effective limit (denom explosion or lltv ≈ 0)
///   - maxLif < WAD:       implicit invariant from the post-maturity lif formula
rule rcfLiquidationBoundedOvershootRepaidUnits(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[0].lltv;
    uint256 maxLif = obligation.collaterals[0].maxLif;
    require maxLif >= WAD();  // implicit invariant: post-maturity lif formula underflows otherwise

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collaterals[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;
    require repaidUnits > 0;

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxRepaid (post-call, exact arithmetic via mathint)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);
    uint256 badDebt = debtBefore > collatValuePerMaxLif ? assert_uint256(debtBefore - collatValuePerMaxLif) : 0;

    require badDebt == 0;  // RCF is deactivated when bad debt accrues

    uint256 effectiveDebt = assert_uint256(debtBefore - badDebt);
    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(effectiveDebt - _maxDebt), WAD(), denom);

    require _maxRepaid < effectiveDebt;  // RCF actually constrains repayment

    // Maxed out the RCF liquidation.
    require actualRepaid == _maxRepaid;

    // Read post-liquidation state
    uint256 collatAfter = collateralOf(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    assert isHealthy(e,obligation, id, borrower);
}

rule rcfLiquidationBoundedOvershootSeizedAssets(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[0].lltv;
    uint256 maxLif = obligation.collaterals[0].maxLif;
    require maxLif >= WAD();  // implicit invariant: post-maturity lif formula underflows otherwise

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collaterals[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateralOf(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;
    require seizedAssets > 0;

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // Mirror maxRepaid (post-call, exact arithmetic via mathint)
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);

    require debtBefore <= collatValuePerMaxLif;  // RCF is deactivated when bad debt accrues

    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - _maxDebt), WAD(), denom);

    // Maxed out the RCF liquidation.
    require actualRepaid == _maxRepaid;

    // Read post-liquidation state
    uint256 collatAfter = collateralOf(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    // compute health (debt-maxDebt) after liquidation
    uint256 newCollatValueDown = CVL_mulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());
    uint256 _newMaxDebt = CVL_mulDivDown(newCollatValueDown, lltv, WAD());

    assert _newMaxDebt >= debtAfter;
}
