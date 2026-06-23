// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired".

For every liquidatable borrower, every seized-collateral index in {0,1,2}, and every amount in the safe
interval an off-chain liquidator computes from the position, `liquidate` (1) does NOT revert and (2) strictly
decreases debt. Covered for both modes (unhealthy lltv == WAD / lltv < WAD, post-maturity) and both entry
paths (repay with parametric repaidUnits, seize with parametric seizedAssets).

The seizing rules need the seized collateral active and priced (otherwise `liquidate` divides by a zero price).
Borrowers they cannot reach (dust / inactive seized collateral) are instead covered by the no-transfer witness
`badDebtCanBeLiquidated` (repaidUnits = seizedAssets = 0): it never reverts and, whenever there is bad debt to
realize, strictly decreases debt via the write-down (with no bad debt, no input can decrease debt). Together
they cover every liquidatable borrower in scope.

Assumptions (LIVENESS): no liquidator gate, well-behaved tokens (transfers summarized NONDET), constant oracle
prices per address. Scope: a 3-collateral market with up to 3 active collaterals, bounded by `loop_iter = 3`.
*/

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Constant oracle price per address.
    function _.price() external => ghostPrice(calledContract) expect(uint256);

    // Market already created; skip touchMarket's creation branch (borrower has debt).
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Well-behaved tokens (transfers never revert).
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Deterministic mulDiv matching contract math; axioms proven in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition getPrice(uint256 collateralIndex, Midnight.CollateralParams[] params) returns uint256 = collateralIndex == 0 ? ghostPrice(params[0].oracle) : collateralIndex == 1 ? ghostPrice(params[1].oracle) : ghostPrice(params[2].oracle);

definition getLltv(uint256 collateralIndex, Midnight.CollateralParams[] params) returns uint256 = collateralIndex == 0 ? params[0].lltv : collateralIndex == 1 ? params[1].lltv : params[2].lltv;

definition getMaxLif(uint256 collateralIndex, Midnight.CollateralParams[] params) returns uint256 = collateralIndex == 0 ? params[0].maxLif : collateralIndex == 1 ? params[1].maxLif : params[2].maxLif;

// Assume the market is already created.
function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

persistent ghost ghostPrice(address) returns uint256;

/// Deterministic ghost for UtilsLib.mulDivDown. Each axiom is proven in MulDiv.spec (rule named per axiom).
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    // Proved in Muldiv.spec : mulDivDownRoundsDown
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;

    // Proved in Muldiv.spec : mulDivDownTightBound
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;

    // Proved in Muldiv.spec : mulDivMonotoneA
    axiom forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 && a1 <= a2 => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);
}

/// Deterministic ghost for UtilsLib.mulDivUp. Each axiom is proven in MulDiv.spec (rule named per axiom).
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    // Proved in Muldiv.spec : mulDivUpRoundsUp
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;

    // Proved in Muldiv.spec : mulDivArgumentLesserThanDenominator
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivUp(a, b, d) <= a;

    // Proved in Muldiv.spec : mulDivZero
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(0, a, d) == 0 && ghostMulDivUp(a, 0, d) == 0;
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivDown(x, y, d);
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivUp(x, y, d);
}

/// Proven in CollateralBitmap.spec; excluded from this conf and only assumed via requireInvariant.
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// Per-collateral validity. lltv/maxLif bounds are verified on created markets (CreatedMarkets.spec, ExactMath.spec).
/// Only the collat*price bound is a LIVENESS no-overflow assumption.
function validCollateralAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) {
    uint256 lltv = market.collateralParams[i].lltv;
    uint256 maxLif = market.collateralParams[i].maxLif;

    require lltv > 0 && lltv <= WAD(), "lltv in (0, WAD] for a created market (in CreatedMarkets.spec)";
    require maxLif >= WAD(), "maxLif >= WAD (maxLifIsAtLeastWad)";
    require lltv < WAD() => lltv * maxLif <= WAD() * (WAD() - 1), "lltv < WAD => lltv*maxLif <= WAD*(WAD-1) (lifTimesLltvStrictBound)";
    require lltv * maxLif <= WAD() * WAD(), "lltv*maxLif <= WAD*WAD (lifTimesLltvIsLessThanOrEqualToOne)";

    address oracle = market.collateralParams[i].oracle;
    require collateral(id, borrower, i) * ghostPrice(oracle) + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "collat*price fits in uint256 for mulDivUp(price, ORACLE_PRICE_SCALE)";
}

/// Shared setup: 3-collateral market with at most collaterals 0,1,2 active, well-behaved env, no liquidator gate, 
/// unlocked, positive debt, totalUnits/withdrawable bounds (Midnight.spec).
function threeCollatSetup(env e, Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 3, "three-collateral market (borrower activates 0, 1, 2 or 3 of them)";
    uint128 bitmap = collateralBitmap(id, borrower);
    require forall uint256 i. i >= 3 => !summaryGetBit(bitmap, i), "at most collaterals 0,1,2 active (<= loop_iter)";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
    validCollateralAt(market, id, borrower, 2);

    require e.msg.value == 0, "liquidate is non-payable";
    require market.liquidatorGate == 0, "no liquidator gate";
    require e.block.timestamp <= max_uint64, "timestamp fits in uint64";
    require market.maturity <= max_uint64, "maturity fits in uint64";

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt, "totalUnits = sumDebt + withdrawable >= this borrower's debt (Midnight.spec)";
    require withdrawable(id) + _debt <= max_uint128, "withdrawable + debt <= sumDebt + withdrawable = totalUnits <= uint128 max (Midnight.spec)";
    require !liquidationLocked(id, borrower), "transient lock is zero at tx start";
    require _debt > 0, "borrower has debt";

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 2);
}

/// Extends threeCollatSetup for the seizing rules: collateralIndex in {0,1,2}, active and priced (constant-index
/// case split keeps concrete struct-array accesses; liquidatedCollatPrice must be non-zero).
function seizablePreamble(env e, Midnight.Market market, bytes32 id, address borrower, uint256 collateralIndex) {
    threeCollatSetup(e, market, id, borrower);
    require collateralIndex == 0 || collateralIndex == 1 || collateralIndex == 2, "seized index in {0,1,2} (<= loop_iter)";
    require summaryGetBit(collateralBitmap(id, borrower), collateralIndex), "the seized collateral is active";
    require getPrice(collateralIndex, market.collateralParams) > 0, "the seized collateral is priced (LIVENESS)";
}

/// maxDebt = sum over all collaterals of collat * price * lltv (down-rounded). 
/// An inactive collateral's term vanishes (its collat == 0 by nonZeroCollateralsAreActivated).
function maxDebtSum(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    mathint contrib0 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 0), ghostPrice(market.collateralParams[0].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[0].lltv, WAD());
    mathint contrib1 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 1), ghostPrice(market.collateralParams[1].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[1].lltv, WAD());
    mathint contrib2 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 2), ghostPrice(market.collateralParams[2].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[2].lltv, WAD());
    return contrib0 + contrib1 + contrib2;
}

/// debtAfter = debt - badDebt, where badDebt = zeroFloorSub chain = max(0, debt - recovery0 - recovery1 - recovery2).
function debtAfterBadDebt(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    mathint recovery0 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 0), ghostPrice(market.collateralParams[0].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[0].maxLif);
    mathint recovery1 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 1), ghostPrice(market.collateralParams[1].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[1].maxLif);
    mathint recovery2 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 2), ghostPrice(market.collateralParams[2].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[2].maxLif);
    mathint _debt = debtOf(id, borrower);
    mathint badDebt = _debt > recovery0 + recovery1 + recovery2 ? _debt - recovery0 - recovery1 - recovery2 : 0;
    return _debt - badDebt;
}

/// Scaffolding facts for the lltv < WAD maxRepaid computation: denominator positive (WAD*WAD - maxLif*lltv >= WAD
/// from validCollateralAt) and per-collateral recovery >= maxDebt contribution (so debtAfter >= maxDebt). 
/// The seized collateral additionally gets a strict recovery > contribution, forcing debtAfter > maxDebt, hence
/// maxRepaid >= 1 (keeps the safe interval non-vacuous for any active seized collateral with quote >= 1 unit).
function lowLltvScaffolding(Midnight.Market market, bytes32 id, address borrower, uint256 collateralIndex) {
    uint256 lltv0 = market.collateralParams[0].lltv;
    uint256 maxLif0 = market.collateralParams[0].maxLif;
    uint256 price0 = ghostPrice(market.collateralParams[0].oracle);
    uint128 collat0 = collateral(id, borrower, 0);

    uint256 lltv1 = market.collateralParams[1].lltv;
    uint256 maxLif1 = market.collateralParams[1].maxLif;
    uint256 price1 = ghostPrice(market.collateralParams[1].oracle);
    uint128 collat1 = collateral(id, borrower, 1);

    uint256 lltv2 = market.collateralParams[2].lltv;
    uint256 maxLif2 = market.collateralParams[2].maxLif;
    uint256 price2 = ghostPrice(market.collateralParams[2].oracle);
    uint128 collat2 = collateral(id, borrower, 2);

    // recovery_i >= maxDebtContrib_i for every collateral
    assert ghostMulDivUp(ghostMulDivUp(collat0, price0, ORACLE_PRICE_SCALE()), WAD(), maxLif0) >= ghostMulDivDown(ghostMulDivDown(collat0, price0, ORACLE_PRICE_SCALE()), lltv0, WAD()), "recovery0 >= maxDebtContrib0 (any valid collateral, incl. inactive)";
    assert ghostMulDivUp(ghostMulDivUp(collat1, price1, ORACLE_PRICE_SCALE()), WAD(), maxLif1) >= ghostMulDivDown(ghostMulDivDown(collat1, price1, ORACLE_PRICE_SCALE()), lltv1, WAD()), "recovery1 >= maxDebtContrib1 (any valid collateral, incl. inactive)";
    assert ghostMulDivUp(ghostMulDivUp(collat2, price2, ORACLE_PRICE_SCALE()), WAD(), maxLif2) >= ghostMulDivDown(ghostMulDivDown(collat2, price2, ORACLE_PRICE_SCALE()), lltv2, WAD()), "recovery2 >= maxDebtContrib2 (any valid collateral, incl. inactive)";

    // Seized collateral: ExactMath denominator bound (=> WAD*WAD - maxLif*lltv >= WAD >= 1) and strict
    // recovery > maxDebtContrib (=> debtAfter > maxDebt, so maxRepaid >= 1; needs collatJ*priceJ >= ORACLE_PRICE_SCALE).
    uint256 lltvJ = getLltv(collateralIndex, market.collateralParams);
    uint256 maxLifJ = getMaxLif(collateralIndex, market.collateralParams);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint128 collatJ = collateral(id, borrower, collateralIndex);
    require maxLifJ * lltvJ <= WAD() * (WAD() - 1), "maxLif*lltv <= WAD*(WAD-1) (lifTimesLltvStrictBound) => WAD*WAD - maxLif*lltv >= WAD >= 1";
    require ghostMulDivUp(ghostMulDivUp(collatJ, priceJ, ORACLE_PRICE_SCALE()), WAD(), maxLifJ) > ghostMulDivDown(ghostMulDivDown(collatJ, priceJ, ORACLE_PRICE_SCALE()), lltvJ, WAD()), "recoveryJ > maxDebtContribJ (seized lltv < WAD, collatJ*priceJ >= ORACLE_PRICE_SCALE)";
}

/// REPAY PATH (repaidUnits > 0, seizedAssets = 0) ///

/// Unhealthy, lltv == WAD: maxRepaid = type(uint256).max, so the RCF check passes unconditionally and the
/// `_position.debt - maxDebt` subtraction is never executed. Only the debt and collateral underflow guards bind.
rule unhealthyLltvFullLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    uint256 maxLif = getMaxLif(collateralIndex, market.collateralParams);
    require getLltv(collateralIndex, market.collateralParams) == WAD(), "lltv == WAD partition (maxRepaid = uint256.max)";

    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require _debt > maxDebtSum(market, id, borrower), "unhealthy: debt > maxDebt";

    require repaidUnits > 0;
    require repaidUnits <= debtAfter, "no debt underflow";
    require ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), priceJ) <= collatJ, "seize fits the seized collateral";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, 0, repaidUnits, borrower, false, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// Unhealthy, lltv < WAD: maxRepaid is finite, so the safe interval is additionally capped by repaidUnits <= maxRepaid.
rule unhealthyLowLltvLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    uint256 lltv = getLltv(collateralIndex, market.collateralParams);
    uint256 maxLif = getMaxLif(collateralIndex, market.collateralParams);
    require lltv < WAD(), "lltv < WAD partition";

    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint maxDebt = maxDebtSum(market, id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require _debt > maxDebt, "unhealthy: debt > maxDebt";

    lowLltvScaffolding(market, id, borrower, collateralIndex);

    // maxRepaid (RCF check) = mulDivUp(debtAfter - maxDebt, WAD*WAD, WAD*WAD - lif*lltv), lif = maxLif here.
    // Reconstructed bit-for-bit so the bound matches the RCF check exactly; denominator > 0 and debtAfter >= maxDebt from lowLltvScaffolding.
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), assert_uint256(WAD() * WAD()), assert_uint256(WAD() * WAD() - maxLif * lltv));
    assert maxRepaid > 0, "it's possible to repay at least one unit";

    require repaidUnits > 0;
    require repaidUnits <= maxRepaid, "RCF check passes";
    require repaidUnits <= debtAfter, "no debt underflow";
    require ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), priceJ) <= collatJ, "seize fits the seized collateral";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, 0, repaidUnits, borrower, false, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// Post-maturity: liquidatable by expiry alone (no health check), RCF / `debt - maxDebt` block skipped. lif <=
/// maxLif post-maturity, so bounding the seize at maxLif (via ghostMulDivDown monotonicity) upper-bounds it.
rule postMaturityLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    require e.block.timestamp > market.maturity, "post-maturity partition (liquidatable by expiry)";

    uint256 maxLif = getMaxLif(collateralIndex, market.collateralParams);
    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);

    require repaidUnits > 0;
    require repaidUnits <= debtAfter, "no debt underflow";
    require ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), priceJ) <= collatJ, "seize (at lif <= maxLif) fits the seized collateral";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, 0, repaidUnits, borrower, true, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// SEIZE PATH (seizedAssets > 0, repaidUnits = 0): contract derives repaidUnits = mulDivUp(mulDivUp(seizedAssets, price, ORACLE_PRICE_SCALE), WAD, lif).
/// Collateral guard is a direct `seizedAssets <= collateral`; debt-underflow / RCF apply to the derived repaidUnits, which is >= 1 (seizedAssets > 0, price > 0) so progress holds.

/// Seize path, unhealthy, lltv == WAD: maxRepaid = uint256.max (RCF auto-passes), lif = maxLif.
rule seizeUnhealthyLltvFullLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    uint256 maxLif = getMaxLif(collateralIndex, market.collateralParams);
    require getLltv(collateralIndex, market.collateralParams) == WAD(), "lltv == WAD partition (maxRepaid = uint256.max)";

    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require _debt > maxDebtSum(market, id, borrower), "unhealthy: debt > maxDebt";

    mathint repaidUnits = ghostMulDivUp(ghostMulDivUp(seizedAssets, priceJ, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    require seizedAssets > 0;
    require seizedAssets <= collatJ, "seize fits the seized collateral";
    require repaidUnits <= debtAfter, "derived repaidUnits: no debt underflow";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, seizedAssets, 0, borrower, false, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// Seize path, unhealthy, lltv < WAD: RCF caps the derived repaidUnits by maxRepaid; same scaffolding applies.
rule seizeUnhealthyLowLltvLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    uint256 lltv = getLltv(collateralIndex, market.collateralParams);
    uint256 maxLif = getMaxLif(collateralIndex, market.collateralParams);
    require lltv < WAD(), "lltv < WAD partition";

    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint maxDebt = maxDebtSum(market, id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require _debt > maxDebt, "unhealthy: debt > maxDebt";

    lowLltvScaffolding(market, id, borrower, collateralIndex);

    // maxRepaid (RCF check) = mulDivUp(debtAfter - maxDebt, WAD*WAD, WAD*WAD - lif*lltv),
    // lif = maxLif here. Reconstructed bit-for-bit so the bound matches the contract's RCF check exactly.
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), assert_uint256(WAD() * WAD()), assert_uint256(WAD() * WAD() - maxLif * lltv));
    assert maxRepaid > 0, "it's possible to repay at least one unit";

    mathint repaidUnits = ghostMulDivUp(ghostMulDivUp(seizedAssets, priceJ, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    require seizedAssets > 0;
    require seizedAssets <= collatJ, "seize fits the seized collateral";
    require repaidUnits <= maxRepaid, "derived repaidUnits: RCF check passes";
    require repaidUnits <= debtAfter, "derived repaidUnits: no debt underflow";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, seizedAssets, 0, borrower, false, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// Seize path, post-maturity: no RCF. lif >= WAD, and the derived repaidUnits = mulDivUp(quote, WAD, lif) is
/// largest at lif = WAD (mulDivUp is antitone in its denominator), so it is upper-bounded by `quote` itself.
rule seizePostMaturityLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 collateralIndex, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower, collateralIndex);

    require e.block.timestamp > market.maturity, "post-maturity partition (liquidatable by expiry)";

    uint128 collatJ = collateral(id, borrower, collateralIndex);
    uint256 priceJ = getPrice(collateralIndex, market.collateralParams);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);

    mathint quoteUp = ghostMulDivUp(seizedAssets, priceJ, ORACLE_PRICE_SCALE());

    require seizedAssets > 0;
    require seizedAssets <= collatJ, "seize fits the seized collateral";
    require quoteUp <= debtAfter, "derived repaidUnits (<= quote since lif >= WAD): no debt underflow";

    bytes data;
    liquidate@withrevert(e, market, collateralIndex, seizedAssets, 0, borrower, true, receiver, 0, data);
    assert !lastReverted;
    assert debtOf(id, borrower) < _debt;
}

/// BAD-DEBT WITNESS (repaidUnits = 0, seizedAssets = 0): any liquidatable borrower can be liquidated with the
/// no-transfer call, which skips the seize/RCF/underflow block entirely (never reverts, any collateral state).
rule badDebtCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver, bool postMaturityMode) {
    bytes32 id = summaryToId(market);
    threeCollatSetup(e, market, id, borrower);

    require postMaturityMode ? e.block.timestamp > market.maturity : !isHealthy(market, id, borrower), "borrower is liquidatable in the chosen mode";

    uint256 _debt = debtOf(id, borrower);

    // (0,0) skips the seize/RCF/underflow block, so the call's only debt effect is the bad-debt write-down:
    // post-debt == debt - badDebt == debtAfterBadDebt. Hence bad debt to realize (debtAfter < debt) => debt strictly drops.
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, postMaturityMode, receiver, 0, data);
    assert !lastReverted;
    assert debtAfter < _debt => debtOf(id, borrower) < _debt;
}
