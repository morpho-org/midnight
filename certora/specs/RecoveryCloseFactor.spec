// SPDX-License-Identifier: GPL-2.0-or-later

/// @notice Draft Certora specification for Recovery Close Factor (RCF) and rcfThreshold
///         properties, scoped to the `liquidate` function.
///
/// Properties 1-2 are general (any number of collaterals).
/// Properties 3-5 assume single-collateral obligations to keep the arithmetic in
/// CVL tractable; the `require obligation.collaterals.length == 1` is clearly marked.
///
/// Key code facts used throughout (Midnight.sol::liquidate):
///   - `originalDebt = debtOf(id, borrower)` = position[id][borrower].debt before any mutation.
///   - Pre-maturity liquidation requires `originalDebt > maxDebt` (line 394).
///   - `maxDebt` and `badDebt` are computed together in the bitmap loop (lines 381-392).
///     For a single-collateral obligation: maxDebt = mulDivDown(mulDivDown(collatOf, price, OPS), lltv, WAD)
///     and badDebt = zeroFloorSub(originalDebt, mulDivUp(mulDivUp(collatOf, price, OPS), WAD, maxLif)).
///   - Bad debt is deducted from position[id][borrower].debt before maxRepaid is computed (line 398).
///   - When `originalDebt > maxDebt`, lif = maxLif (line 410).
///   - maxRepaid = mulDivUp(debtOf(id,borrower) - maxDebt, WAD, WAD - mulDivUp(lif, lltv, WAD))
///     where debtOf is read AFTER bad debt deduction, i.e. effectiveDebt (line 427).
///   - Bypass: repaidUnits > maxRepaid is allowed only if
///       collatOf.mulDivDown(price, OPS).mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < rcfThreshold (line 430).
///   - zeroFloorSub always returns >= 0, so bypass is unreachable when rcfThreshold = 0.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isHealthy(Midnight.Obligation obligation, bytes32 id, address borrower) external returns (bool) envfree;

    /// Oracle prices are fixed within a single transaction (no re-entrancy price manipulation).
    function _.price() external => CVL_price(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);

    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => summaryMulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => summaryMulDivUp(a, b, denominator);

    // Hook on callbacks, this adds no assumption: see FlashLiquidateCallback.sol and the summaries below.
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => DISPATCHER(true);
    function _.onLiquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => DISPATCHER(true);
    function FlashLiquidateCallback.startFlashloan(address token, uint256 amount) internal => CVL_flashLoanStart(token, amount);
    function FlashLiquidateCallback.endFlashloan(address token, uint256 amount) internal => CVL_flashLoanEnd(token, amount);

    // Assume ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing, no blacklisting, no transfer limits.
    function _.transfer(address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, a, v) expect(bool);
    function _.transferFrom(address src, address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, src, a, v) expect(bool);
}

/// HELPERS ///

// IdLib summary: remember the last id returned by toId.
// Used to bind the obligation id to the pre/post call state in each rule.
persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

// ERC20 summaries.

// Token balances: token => user => balance.
ghost mapping(address => mapping(address => uint256)) tokenBalances;

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    // Non-deterministically set success, which allows to simulate permissions.
    bool success;
    if (success) {
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

// UtilsLib summaries: msb is deterministic; mulDivDown and mulDivUp use mathint ghosts
// so that algebraic axioms (proved separately) can be added per-rule on demand.
ghost CVL_msb(uint256) returns uint256;

/// mathint-level ghosts: deterministic over arbitrary-precision integers, no overflow.
persistent ghost summaryMulDivDownM(mathint, mathint, mathint) returns mathint;
persistent ghost summaryMulDivUpM(mathint, mathint, mathint) returns mathint;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) { revert(); }
    return require_uint256(summaryMulDivDownM(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) { revert(); }
    return require_uint256(summaryMulDivUpM(a, b, d));
}

// Oracle price summary: deterministic within a transaction.
ghost CVL_price(address) returns uint256;

// Constants matching ConstantsLib.sol.
definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// CVL mirror of the in-code maxDebt contribution from a single collateral (Midnight.sol line 387):
//   floor(floor(collatAmount * price / ORACLE_PRICE_SCALE) * lltv / WAD)
function singleCollatMaxDebt(uint256 collatAmount, uint256 price, uint256 lltv) returns mathint {
    return summaryMulDivDownM(summaryMulDivDownM(collatAmount, price, ORACLE_PRICE_SCALE()), lltv, WAD());
}

// CVL mirror of the in-code maxRepaid formula (Midnight.sol line 427):
//   ceil((debtOf(id,borrower) - maxDebt) * WAD / (WAD - ceil(lif * lltv / WAD)))
// debtOf(id,borrower) is read AFTER bad debt deduction — passed here as `debt` = effectiveDebt.
// Requires: debt >= _maxDebt and lifTimesLltv < WAD (else denominator <= 0,
// which causes the Solidity code to revert for non-zero liquidation amounts).
function computeMaxRepaid(mathint debt, mathint _maxDebt, uint256 lif, uint256 lltv) returns mathint {
    mathint lifTimesLltv = summaryMulDivUpM(lif, lltv, WAD());

    // Denominator must be positive; lif * lltv >= WAD causes a revert in Solidity.
    require lifTimesLltv < to_mathint(WAD());
    mathint denom = to_mathint(WAD()) - lifTimesLltv;
    return summaryMulDivUpM(debt - _maxDebt, WAD(), denom);
}

// Algebraic axioms for mulDivDown/Up — proved separately in Healthiness.spec.
// These are added as `require forall` per-rule to avoid globally assuming them
// (following the pattern from Healthiness.spec).

definition axiomUpPositive(mathint a, mathint b, mathint d) returns bool =
    a > 0 && b > 0 && d > 0 => summaryMulDivUpM(a, b, d) >= 1;

definition axiomDownNonNeg(mathint a, mathint b, mathint d) returns bool =
    a >= 0 && b >= 0 && d > 0 => summaryMulDivDownM(a, b, d) >= 0;

definition axiomUpNonNeg(mathint a, mathint b, mathint d) returns bool =
    a >= 0 && b >= 0 && d > 0 => summaryMulDivUpM(a, b, d) >= 0;

definition axiomUpZero(mathint a, mathint b, mathint d) returns bool =
    d > 0 && (a == 0 || b == 0) => summaryMulDivUpM(a, b, d) == 0;

definition axiomDownZero(mathint a, mathint b, mathint d) returns bool =
    d > 0 && (a == 0 || b == 0) => summaryMulDivDownM(a, b, d) == 0;

definition axiomDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool =
    0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);

definition axiomUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool =
    0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => summaryMulDivUpM(a1, b, d) <= summaryMulDivUpM(a2, b, d);

definition axiomDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool =
    0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => summaryMulDivDownM(a, b1, d) <= summaryMulDivDownM(a, b2, d);

definition axiomUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool =
    0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => summaryMulDivUpM(a, b, d1) >= summaryMulDivUpM(a, b, d2);

// mulDivUp(a, d, d) = a  (combined with monotonicity gives upper bounds)
definition axiomUpSelf(mathint a, mathint d) returns bool =
    a >= 0 && d > 0 => summaryMulDivUpM(a, d, d) == a;

definition axiomDownSelf(mathint a, mathint d) returns bool =
    a >= 0 && d > 0 => summaryMulDivDownM(a, d, d) == a;

persistent ghost mapping(address => mathint) flashloans {
    init_state axiom (forall address token. flashloans[token] == 0);
}

function CVL_flashLoanStart(address token, uint256 amount) {
    flashloans[token] = flashloans[token] + amount;
}

function CVL_flashLoanEnd(address token, uint256 amount) {
    flashloans[token] = flashloans[token] - amount;
}

/// RULES ///

/// Property 1: rcfRequiresUnhealthyPreMaturity
///
/// Before maturity, `liquidate` can only execute with non-zero amounts if the
/// borrower was unhealthy (debt > maxDebt). This follows from the liquidatability
/// check: `require(block.timestamp > maturity || originalDebt > maxDebt)`.
/// Consequence: in the pre-maturity RCF branch, lif is always equal to maxLif
/// (the `originalDebt > maxDebt` arm of the lif ternary is taken).
rule rcfRequiresUnhealthyPreMaturity(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id;
    bool healthyBefore = isHealthy(obligation, id, borrower);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // Bind id to the obligation used inside this liquidate call.
    require id == lastId;

    assert e.block.timestamp <= obligation.maturity && (seizedAssets > 0 || repaidUnits > 0) => !healthyBefore, "pre-maturity non-zero liquidation requires the position to be unhealthy";
}

/// Property 2: prematurityLiquidationHealthyImpliesBypass
///
/// A position can only be healthy after a pre-maturity liquidation if rcfThreshold > 0.
/// Proof sketch: the bypass path requires `zeroFloorSub(collatValue/lif, maxRepaid) < rcfThreshold`.
/// Since zeroFloorSub always returns a uint256 (>= 0), the condition is satisfiable
/// only when rcfThreshold > 0. When rcfThreshold = 0, repaidUnits is bounded by
/// maxRepaid, which keeps the position at or below the health boundary.
rule prematurityLiquidationHealthyImpliesBypass(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id;

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require data.length == 0;
    require id == lastId;

    bool healthyAfter = isHealthy(obligation, id, borrower);

    assert e.block.timestamp <= obligation.maturity && healthyAfter => obligation.rcfThreshold > 0, "position can only be healthy after pre-maturity liquidation if rcfThreshold > 0";
}

/// Property 3: rcfBypassConditionNecessity
///
/// When the rcfThreshold bypass is triggered (position becomes healthy after a
/// pre-maturity liquidation), the bypass condition from the code must hold:
///   collatBefore * price / ORACLE_PRICE_SCALE / maxLif - maxRepaid < rcfThreshold
/// where maxRepaid is computed using the pre-call debt and collateral.
/// This verifies that a bypass is always warranted: the liquidated collateral, valued
/// at maxLif, cannot cover more than rcfThreshold units above the maxRepaid threshold.
///
/// Assumes: single-collateral obligation (collaterals.length == 1, collateralIndex = 0).
rule rcfBypassConditionNecessity(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    // Single-collateral assumption: simplifies maxDebt/maxRepaid computation in CVL.
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[collateralIndex].lltv;
    uint256 _maxLif = obligation.collaterals[collateralIndex].maxLif;
    address oracle = obligation.collaterals[collateralIndex].oracle;
    uint256 price = CVL_price(oracle);

    // Read pre-call state. `id` is bound to the actual obligation id after the call.
    bytes32 id;
    uint256 collatBefore = currentContract.position[id][borrower].collateral[collateralIndex];
    uint256 debtBefore = currentContract.position[id][borrower].debt;

    // Compute maxDebt and maxRepaid mirroring the in-code formulas.
    // Property 1 guarantees debtBefore > _maxDebt in the RCF branch.
    mathint _maxDebt = singleCollatMaxDebt(collatBefore, price, lltv);
    require to_mathint(debtBefore) > _maxDebt; // liquidatability check — uses originalDebt (Midnight.sol line 394)

    // Mirror bad debt deduction (Midnight.sol lines 379-406):
    //   badDebt starts as originalDebt, reduced by mulDivUp(collatOf, price, OPS).mulDivUp(WAD, maxLif) per collateral.
    //   For single-collateral: badDebt = zeroFloorSub(originalDebt, mulDivUp(mulDivUp(collatOf, price, OPS), WAD, maxLif))
    mathint collatValuePerMaxLif = summaryMulDivUpM(
        summaryMulDivUpM(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), _maxLif
    );
    mathint badDebt = to_mathint(debtBefore) > collatValuePerMaxLif
        ? to_mathint(debtBefore) - collatValuePerMaxLif
        : 0;
    mathint effectiveDebt = to_mathint(debtBefore) - badDebt; // position[id][borrower].debt after bad debt deduction (line 398)
    require effectiveDebt >= _maxDebt; // Solidity invariant: "Note that debt >= maxDebt in this branch" (line 426)

    mathint _maxRepaid = computeMaxRepaid(effectiveDebt, _maxDebt, _maxLif, lltv);

    // Algebraic constraints on the mulDiv ghosts needed for this rule.
    require forall mathint a. forall mathint b. forall mathint d. axiomUpPositive(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomDownNonNeg(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomUpNonNeg(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomUpZero(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomDownZero(a, b, d);
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d);
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d);
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d);
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2);
    require forall mathint a. forall mathint d. axiomUpSelf(a, d);
    require forall mathint a. forall mathint d. axiomDownSelf(a, d);

    require data.length == 0;

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    bool healthyAfter = isHealthy(obligation, id, borrower);

    // Bypass condition: remaining collateral value (per lif) above maxRepaid < rcfThreshold.
    // Mirrors: collatOf.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(WAD, lif).zeroFloorSub(maxRepaid)
    //           < rcfThreshold
    mathint collatValuePerLif = summaryMulDivDownM(summaryMulDivDownM(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), _maxLif);
    mathint bypassExcess = collatValuePerLif > _maxRepaid ? collatValuePerLif - _maxRepaid : 0;

    assert e.block.timestamp <= obligation.maturity && healthyAfter => bypassExcess < to_mathint(obligation.rcfThreshold), "when position heals pre-maturity, bypass condition must hold quantitatively";
}

/// Property 4: zeroRcfThresholdAlwaysEnforcesRcf
///
/// When rcfThreshold = 0, the bypass path requires `zeroFloorSub(...) < 0`, which is
/// impossible for any uint256 value. Therefore, `repaidUnits <= maxRepaid` is always
/// enforced, and the RCF bound is never relaxed.
/// This is a structural soundness check: it verifies the bypass guard is correctly
/// written (< rcfThreshold, not <= rcfThreshold).
///
/// Assumes: single-collateral obligation.
rule zeroRcfThresholdAlwaysEnforcesRcf(env e, Midnight.Obligation obligation, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 lltv = obligation.collaterals[collateralIndex].lltv;
    uint256 _maxLif = obligation.collaterals[collateralIndex].maxLif;
    address oracle = obligation.collaterals[collateralIndex].oracle;
    uint256 price = CVL_price(oracle);

    bytes32 id;
    uint256 collatBefore = currentContract.position[id][borrower].collateral[collateralIndex];
    uint256 debtBefore = currentContract.position[id][borrower].debt;

    mathint _maxDebt = singleCollatMaxDebt(collatBefore, price, lltv);
    require to_mathint(debtBefore) > _maxDebt; // liquidatability check — uses originalDebt (Midnight.sol line 394)

    // Mirror bad debt deduction (Midnight.sol lines 379-406):
    //   badDebt starts as originalDebt, reduced by mulDivUp(collatOf, price, OPS).mulDivUp(WAD, maxLif) per collateral.
    //   For single-collateral: badDebt = zeroFloorSub(originalDebt, mulDivUp(mulDivUp(collatOf, price, OPS), WAD, maxLif))
    mathint collatValuePerMaxLif = summaryMulDivUpM(
        summaryMulDivUpM(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), _maxLif
    );
    mathint badDebt = to_mathint(debtBefore) > collatValuePerMaxLif
        ? to_mathint(debtBefore) - collatValuePerMaxLif
        : 0;
    mathint effectiveDebt = to_mathint(debtBefore) - badDebt; // position[id][borrower].debt after bad debt deduction (line 398)
    require effectiveDebt >= _maxDebt; // Solidity invariant: "Note that debt >= maxDebt in this branch" (line 426)

    // Protocol invariant: lif * lltv < WAD^2 ensures effectiveDebt >= maxDebt after bad debt.
    require to_mathint(_maxLif) * to_mathint(lltv) <= to_mathint(WAD()) * to_mathint(WAD());

    mathint _maxRepaid = computeMaxRepaid(effectiveDebt, _maxDebt, _maxLif, lltv);

    // Algebraic constraints on the mulDiv ghosts needed for this rule.
    require forall mathint a. forall mathint b. forall mathint d. axiomUpPositive(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomDownNonNeg(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomUpNonNeg(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomUpZero(a, b, d);
    require forall mathint a. forall mathint b. forall mathint d. axiomDownZero(a, b, d);
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomDownMonotoneA(a1, a2, b, d);
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. axiomUpMonotoneA(a1, a2, b, d);
    require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. axiomDownMonotoneB(a, b1, b2, d);
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. axiomUpMonotoneD(a, b, d1, d2);
    require forall mathint a. forall mathint d. axiomUpSelf(a, d);
    require forall mathint a. forall mathint d. axiomDownSelf(a, d);

    // The bypass is disabled.
    require obligation.rcfThreshold == 0;
    require e.block.timestamp <= obligation.maturity;
    require seizedAssets > 0 || repaidUnits > 0;

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    // With rcfThreshold = 0, the only valid path is `repaidUnits <= maxRepaid`.
    assert to_mathint(repaidUnits) <= _maxRepaid, "rcfThreshold=0 must enforce repaidUnits <= maxRepaid on all pre-maturity liquidations";
}

/// Property 5: lifEqualsMaxLifInRcfBranch
///
/// In the pre-maturity RCF branch, since originalDebt > maxDebt holds (Property 1),
/// the `lif` factor is always `maxLif`. We verify this indirectly via the seized assets
/// formula: when `repaidUnits > 0` is given as input, the returned `seizedAssets` must
/// match `mulDivDown(mulDivDown(repaidUnits, maxLif, WAD), ORACLE_PRICE_SCALE, price)`.
/// Any deviation would imply a different lif was used.
///
/// Assumes: single-collateral obligation, repaidUnits input (seizedAssets = 0).
rule lifEqualsMaxLifInRcfBranch(env e, Midnight.Obligation obligation, uint256 repaidUnits, address borrower, bytes data) {
    require obligation.collaterals.length == 1;
    uint256 collateralIndex = 0;

    uint256 _maxLif = obligation.collaterals[collateralIndex].maxLif;
    address oracle = obligation.collaterals[collateralIndex].oracle;
    uint256 price = CVL_price(oracle);
    require price > 0; // avoid division by zero in the seized assets formula

    uint256 seizedAssetsOut;
    uint256 repaidUnitsOut;

    // Pass seizedAssets = 0 so the code enters the `repaidUnits > 0` branch:
    //   seizedAssets = mulDivDown(mulDivDown(repaidUnits, lif, WAD), ORACLE_PRICE_SCALE, price)
    seizedAssetsOut, repaidUnitsOut = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    // Expected seized assets if lif = maxLif (as guaranteed by Property 1 pre-maturity).
    mathint expectedSeized = summaryMulDivDownM(summaryMulDivDownM(repaidUnits, _maxLif, WAD()), ORACLE_PRICE_SCALE(), price);

    assert e.block.timestamp <= obligation.maturity && repaidUnits > 0 => to_mathint(seizedAssetsOut) == expectedSeized, "pre-maturity seized assets must be computed with lif = maxLif";
}
