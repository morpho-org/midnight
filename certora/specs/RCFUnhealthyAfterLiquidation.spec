// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that an RCF-limited liquidation (actualRepaid == maxRepaid) makes the
// position healthy. Uses exact mulDiv implementations (floor/ceiling arithmetic)
// because the proof requires lower bounds on mulDivUp — specifically that
// mulDivUp(a, WAD, denom) * denom >= a * WAD — which the relational axioms in
// Healthiness.spec do not provide.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => CVL_msb(bitmap);
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

    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function activatedCollaterals(bytes32, address) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
}

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

ghost CVL_msb(uint128) returns uint256;

persistent ghost CVL_price(address) returns uint256;

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

rule rcfLiquidationOvershootBoundedRepaidUnits(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require obligation.collateralParams.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collateralParams[0].lltv;
    uint256 maxLif = obligation.collateralParams[0].maxLif;
    require maxLif >= WAD();  // implicit invariant: post-maturity lif formula underflows otherwise

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collateralParams[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;
    require repaidUnits > 0;

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require id == lastId;

    // Mirror maxRepaid
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
    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    assert isHealthy(e, obligation, id, borrower);
}

rule rcfLiquidationBoundedOvershootSeizedAssets(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require obligation.collateralParams.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collateralParams[0].lltv;
    uint256 maxLif = obligation.collateralParams[0].maxLif;
    require maxLif >= WAD();  // implicit invariant: post-maturity lif formula underflows otherwise

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collateralParams[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;
    require seizedAssets > 0;

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require id == lastId;

    // Mirror maxRepaid
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
    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    // compute health after liquidation
    uint256 newCollatValueDown = CVL_mulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());
    uint256 _newMaxDebt = CVL_mulDivDown(newCollatValueDown, lltv, WAD());

    assert _newMaxDebt >= debtAfter;
}

// repaidUnits > 0 path:
//   seizedAssets = repaidUnits.mulDivDown(lif, WAD).mulDivDown(OPS, price) — two floors, net error ≤ 1 collateral unit.
//   That 1 missing collateral unit propagates through newMaxDebt with a factor of price, giving
//   an extra floor(floor(price / OPS) * lltv / WAD) debt units of surplus.
//   Additionally, ceil in maxRepaid adds at most 1 debt unit.
//   Total surplus ≤ 1 + floor(floor(price / OPS) * lltv / WAD).
rule rcfLiquidationSurplusBoundedRepaid(env e, Midnight.Obligation obligation, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require obligation.collateralParams.length == 1;
    uint256 collateralIndex = 0;
    uint256 seizedAssets = 0;

    uint256 lltv = obligation.collateralParams[0].lltv;
    uint256 maxLif = obligation.collateralParams[0].maxLif;
    require maxLif >= WAD();

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collateralParams[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require repaidUnits > 0;

    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());
    require debtBefore > maxDebt;  // pre-maturity unhealthy → lif = maxLif

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);
    require debtBefore <= collatValuePerMaxLif;  // no bad debt

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require id == lastId;

    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - maxDebt), WAD(), denom);

    require maxRepaid < debtBefore;  // RCF actually constrains repayment
    require actualRepaid == maxRepaid;  // RCF cap was hit

    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    // liftedSeized = floor(maxRepaid * maxLif / WAD): the collateral-unit equivalent of maxRepaid.
    // These two requires encode the floor round-trip property for seizedAssets:
    //   seizedAssets = floor(floor(maxRepaid * maxLif / WAD) * OPS / price)
    // Upper bound: floor(x * OPS/price) * price/OPS ≤ x  → seizedActual * price/OPS ≤ liftedSeized
    // Lower bound: floor(x * OPS/price) * price/OPS ≥ x - price/OPS - 1  → seizedActual * price/OPS ≥ liftedSeized - floor(price/OPS) - 1
    // Without these the prover must re-derive the bound through 4 levels of nested non-linear arithmetic.
    uint256 seizedActual = assert_uint256(collatBefore - collatAfter);
    uint256 liftedSeized = CVL_mulDivDown(maxRepaid, maxLif, WAD());
    require CVL_mulDivDown(seizedActual, price, ORACLE_PRICE_SCALE()) <= liftedSeized;
    require to_mathint(CVL_mulDivDown(seizedActual, price, ORACLE_PRICE_SCALE()))
        >= to_mathint(liftedSeized) - to_mathint(CVL_mulDivDown(1, price, ORACLE_PRICE_SCALE())) - 1;

    uint256 newCollatValueDown = CVL_mulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());
    uint256 newMaxDebt = CVL_mulDivDown(newCollatValueDown, lltv, WAD());

    // Bound derivation. From actualRepaid = ceil((debtBefore - maxDebt) * WAD / (WAD - lifTimesLltv))
    // in real arithmetic: actualRepaid * lifTimesLltv / WAD ≤ maxDebt - debtAfter, with slack < 1.
    // newMaxDebt ≈ maxDebt - actualRepaid * lifTimesLltv_real / WAD. Since lifTimesLltv is ceiled,
    // lifTimesLltv_ceil - lifTimesLltv_real < 1/WAD, so the gap times actualRepaid contributes up to
    // actualRepaid/WAD extra surplus — this term dominates when denom is small (actualRepaid large).
    // Plus floor(floor(price/OPS) * lltv/WAD) + 1 from 1 collateral unit miss in seizedAssets × price,
    // plus 1 from ceil slack in maxRepaid.
    uint256 seizedAssetsRoundingError = CVL_mulDivDown(CVL_mulDivDown(1, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    assert to_mathint(newMaxDebt) - to_mathint(debtAfter)
        <= (to_mathint(actualRepaid) + to_mathint(WAD()) - 1) / to_mathint(WAD())
            + 2 + to_mathint(seizedAssetsRoundingError);
}

// seizedAssets > 0 path:
//   repaidUnits = seizedAssets.mulDivUp(price, OPS).mulDivUp(WAD, lif) — two ceils, error ≤ 2 debt units.
//   newMaxDebt uses exact seizedAssets (given), so no price-multiplied rounding.
//   Total surplus ≤ 2.
rule rcfLiquidationSurplusBoundedSeized(env e, Midnight.Obligation obligation, uint256 seizedAssets, address borrower, address receiver, address callback, bytes data) {
    require obligation.collateralParams.length == 1;
    uint256 collateralIndex = 0;
    uint256 repaidUnits = 0;

    uint256 lltv = obligation.collateralParams[0].lltv;
    uint256 maxLif = obligation.collateralParams[0].maxLif;
    require maxLif >= WAD();

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collateralParams[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0;

    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());
    require debtBefore > maxDebt;  // pre-maturity unhealthy → lif = maxLif

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);
    require debtBefore <= collatValuePerMaxLif;  // no bad debt

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require id == lastId;

    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - maxDebt), WAD(), denom);

    require maxRepaid < debtBefore;  // RCF actually constrains repayment
    require actualRepaid == maxRepaid;  // RCF cap was hit

    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);

    uint256 newCollatValueDown = CVL_mulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());
    uint256 newMaxDebt = CVL_mulDivDown(newCollatValueDown, lltv, WAD());

    // Two ceils in repaidUnits = seizedAssets.mulDivUp(price, OPS).mulDivUp(WAD, lif) → surplus ≤ 2.
    assert to_mathint(newMaxDebt) - to_mathint(debtAfter) <= 2;
}

// assume badDebt is zero
rule healthyAfterRcfLiquidation(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require obligation.collateralParams.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collateralParams[0].lltv;
    uint256 maxLif = obligation.collateralParams[0].maxLif;
    require maxLif >= WAD();  // implicit invariant: post-maturity lif formula underflows otherwise

    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD(), "See lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec";
    uint256 price = CVL_price(obligation.collateralParams[0].oracle);

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    require collatBefore > 0;
    require activatedCollaterals(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require e.block.timestamp < obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    uint256 actualRepaid;
    _, actualRepaid = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require id == lastId;

    // Mirror maxRepaid
    uint256 collatValueDown = CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 _maxDebt = CVL_mulDivDown(collatValueDown, lltv, WAD());

    uint256 collatValueUp = CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 collatValuePerMaxLif = CVL_mulDivUp(collatValueUp, WAD(), maxLif);

    // assume no badDebt accrues.
    require debtBefore <= collatValuePerMaxLif;

    uint256 denom = assert_uint256(WAD() - lifTimesLltv);
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - _maxDebt), WAD(), denom);

    // Maxed out the RCF liquidation.
    require actualRepaid == _maxRepaid;

    assert isHealthyNoBitmap(obligation, id, borrower);
}
