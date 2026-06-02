// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired" — full strength.

Range liveness + progress (3-collateral, parametric amount): for every liquidatable borrower and every amount
in the safe interval an off-chain liquidator computes from the position, `liquidate` (1) does NOT revert and
(2) strictly decreases debt. Proven for both modes (unhealthy lltv == WAD / lltv < WAD, post-maturity) and both
entry paths (repay with parametric repaidUnits, seize with parametric seizedAssets).

Borrowers the seizing rules cannot reach (dust / inactive collateral 0, where a seizing call would divide by a
zero liquidatedCollatPrice) are covered by the no-transfer bad-debt witness `badDebtCanBeLiquidated`
(repaidUnits = 0, seizedAssets = 0). Together they cover every liquidatable borrower in scope.

The safe amount is reconstructed in CVL from the contract's own quantities. Because `mulDiv*` are summarized as
deterministic ghosts, those values are bit-for-bit identical to the ones inside `liquidate`, so bounding the
amount by them neutralises each revert site (annotated per-require with the Midnight.sol line). Over-constraining
only WEAKENS the result (never unsound); under-constraining surfaces as an `assert !lastReverted` counterexample.

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

    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition MAX_UINT128() returns mathint = (1 << 128) - 1;

definition MAX_TIMESTAMP() returns mathint = 1 << 64;

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivDown(a, b, d) <= a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivDown(a, d, d) == a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivDown(0, a, d) == 0 && ghostMulDivDown(a, 0, d) == 0;

    /// Monotonicity in each numerator factor. Sound (floor(a*b/d) is nondecreasing in a and b). Used by the
    /// post-maturity range rule to upper-bound the decayed-lif seize by the maxLif seize (lif <= maxLif).
    axiom forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 && a1 <= a2 => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);
    axiom forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 && b1 <= b2 => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivUp(a, b, d) <= a;

    /// Mirror of ghostMulDivDown's `b <= d => <= a` axiom. Sound: result * d >= a*b >= a*d.
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b >= d => ghostMulDivUp(a, b, d) >= a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(a, d, d) == a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(0, a, d) == 0 && ghostMulDivUp(a, 0, d) == 0;
    axiom forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 && a1 <= a2 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);

    /// Antitone in the denominator. Sound (ceil(a*b/d) is nonincreasing in d). Used by the post-maturity seize
    /// path to upper-bound the derived repaidUnits (lif in the denominator, lif >= WAD) by its value at lif = WAD.
    axiom forall uint256 a. forall uint256 b. forall uint256 d1. forall uint256 d2. d1 > 0 && d1 <= d2 => ghostMulDivUp(a, b, d1) >= ghostMulDivUp(a, b, d2);
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

strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

/// Per-collateral validity (lltv, maxLif, ExactMath bounds, liveness bound on collat * price).
function validCollateralAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) {
    uint256 lltv = market.collateralParams[i].lltv;
    uint256 maxLif = market.collateralParams[i].maxLif;

    require lltv > 0 && lltv <= WAD(), "valid lltv (touchMarket)";
    require maxLif >= WAD(), "valid maxLif (touchMarket)";
    require lltv < WAD() => to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "ExactMath: lltv*maxLif <= WAD*(WAD-1) when lltv<WAD";
    require to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * to_mathint(WAD()), "ExactMath: lltv*maxLif <= WAD*WAD";

    address oracle = market.collateralParams[i].oracle;
    require to_mathint(collateral(id, borrower, i)) * to_mathint(summaryPrice(oracle)) <= to_mathint(ORACLE_PRICE_SCALE()) * to_mathint(WAD()) * MAX_UINT128(), "oracle-quoted collat fits in uint128*WAD (LIVENESS)";
}

/// Shared setup: 3-collateral market with at most collaterals 0,1,2 active (loop runs <= loop_iter), well-behaved
/// env, no liquidator gate, unlocked, positive debt, totalUnits/withdrawable bounds (Midnight.spec). Does NOT
/// assume which collateral is active.
function threeCollatSetup(env e, Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 3, "three-collateral market (borrower activates 0, 1, 2 or 3 of them)";
    uint128 bitmap = collateralBitmap(id, borrower);
    require forall uint256 i. i >= 3 => !summaryGetBit(bitmap, i), "at most collaterals 0,1,2 active (<= loop_iter)";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
    validCollateralAt(market, id, borrower, 2);

    require e.msg.value == 0, "liquidate is non-payable";
    require market.liquidatorGate == 0, "no liquidator gate (LIVENESS)";
    require e.block.timestamp < MAX_TIMESTAMP(), "timestamp fits in uint64";
    require market.maturity < MAX_TIMESTAMP(), "maturity fits in uint64";

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt, "totalUnits = sumDebt + withdrawable >= this borrower's debt (Midnight.spec)";
    require to_mathint(withdrawable(id)) + to_mathint(_debt) <= MAX_UINT128(), "withdrawable + debt <= sumDebt + withdrawable = totalUnits <= uint128 max (Midnight.spec)";
    require !liquidationLocked(id, borrower), "transient lock is zero at tx start";
    require _debt > 0, "borrower has debt";

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 2);
}

/// Extends threeCollatSetup for the seizing rules: collateral 0 (the seized one) is active and priced, so the
/// liquidatedCollatPrice is non-zero (the seize/RCF block divides by it).
function seizablePreamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    threeCollatSetup(e, market, id, borrower);
    require summaryGetBit(collateralBitmap(id, borrower), 0), "collateral 0 (the seized collateral) is active";
    require summaryPrice(market.collateralParams[0].oracle) > 0, "collateral 0 is priced (LIVENESS)";
}

/// maxDebt = sum over all collaterals of collat * price * lltv (down-rounded). An inactive collateral's term
/// vanishes (its collat == 0 by nonZeroCollateralsAreActivated).
function maxDebtSum(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    mathint contrib0 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 0), summaryPrice(market.collateralParams[0].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[0].lltv, WAD());
    mathint contrib1 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 1), summaryPrice(market.collateralParams[1].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[1].lltv, WAD());
    mathint contrib2 = ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, 2), summaryPrice(market.collateralParams[2].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[2].lltv, WAD());
    return contrib0 + contrib1 + contrib2;
}

/// debtAfter = debt - badDebt, where badDebt = zeroFloorSub chain = max(0, debt - recovery0 - recovery1 - recovery2).
function debtAfterBadDebt(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    mathint recovery0 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 0), summaryPrice(market.collateralParams[0].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[0].maxLif);
    mathint recovery1 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 1), summaryPrice(market.collateralParams[1].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[1].maxLif);
    mathint recovery2 = ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, 2), summaryPrice(market.collateralParams[2].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[2].maxLif);
    mathint _debt = debtOf(id, borrower);
    mathint badDebt = _debt > recovery0 + recovery1 + recovery2 ? _debt - recovery0 - recovery1 - recovery2 : 0;
    return _debt - badDebt;
}

/// Scaffolding facts for the lltv < WAD maxRepaid computation: denominator positive (WAD*WAD - maxLif*lltv >= WAD
/// from validCollateralAt) and per-collateral recovery >= maxDebt contribution (so debtAfter >= maxDebt).
function lowLltvScaffolding(Midnight.Market market, bytes32 id, address borrower) {
    uint256 lltv0 = market.collateralParams[0].lltv;
    uint256 maxLif0 = market.collateralParams[0].maxLif;
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint128 collat0 = collateral(id, borrower, 0);

    uint256 lltv1 = market.collateralParams[1].lltv;
    uint256 maxLif1 = market.collateralParams[1].maxLif;
    uint256 price1 = summaryPrice(market.collateralParams[1].oracle);
    uint128 collat1 = collateral(id, borrower, 1);

    uint256 lltv2 = market.collateralParams[2].lltv;
    uint256 maxLif2 = market.collateralParams[2].maxLif;
    uint256 price2 = summaryPrice(market.collateralParams[2].oracle);
    uint128 collat2 = collateral(id, borrower, 2);

    require to_mathint(maxLif0) * to_mathint(lltv0) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1), "WAD*(WAD-1) ExactMath bound (touchMarket) => WAD*WAD - maxLif*lltv >= WAD >= 1";
    require to_mathint(ghostMulDivUp(ghostMulDivUp(collat0, price0, ORACLE_PRICE_SCALE()), WAD(), maxLif0)) > to_mathint(ghostMulDivDown(ghostMulDivDown(collat0, price0, ORACLE_PRICE_SCALE()), lltv0, WAD())), "recovery0 > maxDebtContrib0 (lltv0 < WAD, collat0*price0 >= ORACLE_PRICE_SCALE)";
    require to_mathint(ghostMulDivUp(ghostMulDivUp(collat1, price1, ORACLE_PRICE_SCALE()), WAD(), maxLif1)) >= to_mathint(ghostMulDivDown(ghostMulDivDown(collat1, price1, ORACLE_PRICE_SCALE()), lltv1, WAD())), "recovery1 >= maxDebtContrib1 (any valid collateral, incl. inactive)";
    require to_mathint(ghostMulDivUp(ghostMulDivUp(collat2, price2, ORACLE_PRICE_SCALE()), WAD(), maxLif2)) >= to_mathint(ghostMulDivDown(ghostMulDivDown(collat2, price2, ORACLE_PRICE_SCALE()), lltv2, WAD())), "recovery2 >= maxDebtContrib2 (any valid collateral, incl. inactive)";
}

/// REPAY PATH (repaidUnits > 0, seizedAssets = 0) ///

/// Unhealthy, lltv == WAD: maxRepaid = type(uint256).max, so the RCF check passes unconditionally and the
/// `_position.debt - maxDebt` subtraction is never executed. Only the debt and collateral underflow guards bind.
rule unhealthyLltvFullLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    uint256 maxLif = market.collateralParams[0].maxLif;
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD partition (maxRepaid = uint256.max)";

    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require to_mathint(_debt) > maxDebtSum(market, id, borrower), "unhealthy: debt > maxDebt";

    require repaidUnits > 0;
    require to_mathint(repaidUnits) <= debtAfter, "no debt underflow (L675)";
    require to_mathint(ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price0)) <= to_mathint(collat0), "seize fits collateral[0] (L669)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, repaidUnits, borrower, false, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// Unhealthy, lltv < WAD: maxRepaid is finite, so the safe interval is additionally capped by repaidUnits <= maxRepaid.
rule unhealthyLowLltvLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    uint256 lltv = market.collateralParams[0].lltv;
    uint256 maxLif = market.collateralParams[0].maxLif;
    require lltv < WAD(), "lltv < WAD partition";

    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint maxDebt = maxDebtSum(market, id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require to_mathint(_debt) > maxDebt, "unhealthy: debt > maxDebt";

    lowLltvScaffolding(market, id, borrower);

    // maxRepaid per contract #944 (L658-660): mulDivUp(debtAfter - maxDebt, WAD*WAD, WAD*WAD - lif*lltv), lif =
    // maxLif here. Reconstructed bit-for-bit so the bound matches the RCF check exactly; denominator > 0 and
    // debtAfter >= maxDebt from lowLltvScaffolding.
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), assert_uint256(to_mathint(WAD()) * to_mathint(WAD())), assert_uint256(to_mathint(WAD()) * to_mathint(WAD()) - to_mathint(maxLif) * to_mathint(lltv)));

    require repaidUnits > 0;
    require to_mathint(repaidUnits) <= maxRepaid, "RCF check passes (L661)";
    require to_mathint(repaidUnits) <= debtAfter, "no debt underflow (L675)";
    require to_mathint(ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price0)) <= to_mathint(collat0), "seize fits collateral[0] (L669)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, repaidUnits, borrower, false, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// Post-maturity: liquidatable by expiry alone (no health check), RCF / `debt - maxDebt` block skipped. lif <=
/// maxLif post-maturity, so bounding the seize at maxLif (via ghostMulDivDown monotonicity) upper-bounds it.
rule postMaturityLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 repaidUnits) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity partition (liquidatable by expiry)";

    uint256 maxLif = market.collateralParams[0].maxLif;
    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);

    require repaidUnits > 0;
    require to_mathint(repaidUnits) <= debtAfter, "no debt underflow (L675)";
    require to_mathint(ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price0)) <= to_mathint(collat0), "seize (at lif <= maxLif) fits collateral[0] (L669)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, repaidUnits, borrower, true, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// SEIZE PATH (seizedAssets > 0, repaidUnits = 0): contract derives repaidUnits (L650) =
/// mulDivUp(mulDivUp(seizedAssets, price0, ORACLE_PRICE_SCALE), WAD, lif). Collateral guard is a direct
/// `seizedAssets <= collateral[0]`; debt-underflow / RCF apply to the derived repaidUnits, which is >= 1
/// (seizedAssets > 0, price0 > 0) so progress holds. ///

/// Seize path, unhealthy, lltv == WAD: maxRepaid = uint256.max (RCF auto-passes), lif = maxLif.
rule seizeUnhealthyLltvFullLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    uint256 maxLif = market.collateralParams[0].maxLif;
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD partition (maxRepaid = uint256.max)";

    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require to_mathint(_debt) > maxDebtSum(market, id, borrower), "unhealthy: debt > maxDebt";

    mathint repaidUnits = ghostMulDivUp(ghostMulDivUp(seizedAssets, price0, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    require seizedAssets > 0;
    require to_mathint(seizedAssets) <= to_mathint(collat0), "seize fits collateral[0] (L669)";
    require repaidUnits <= debtAfter, "derived repaidUnits: no debt underflow (L675)";

    bytes data;
    liquidate@withrevert(e, market, 0, seizedAssets, 0, borrower, false, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// Seize path, unhealthy, lltv < WAD: RCF caps the derived repaidUnits by maxRepaid; same scaffolding applies.
rule seizeUnhealthyLowLltvLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    uint256 lltv = market.collateralParams[0].lltv;
    uint256 maxLif = market.collateralParams[0].maxLif;
    require lltv < WAD(), "lltv < WAD partition";

    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint maxDebt = maxDebtSum(market, id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);
    require to_mathint(_debt) > maxDebt, "unhealthy: debt > maxDebt";

    lowLltvScaffolding(market, id, borrower);

    // maxRepaid per contract #944 (L658-660): mulDivUp(debtAfter - maxDebt, WAD*WAD, WAD*WAD - lif*lltv),
    // lif = maxLif here. Reconstructed bit-for-bit so the bound matches the contract's RCF check exactly.
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), assert_uint256(to_mathint(WAD()) * to_mathint(WAD())), assert_uint256(to_mathint(WAD()) * to_mathint(WAD()) - to_mathint(maxLif) * to_mathint(lltv)));

    mathint repaidUnits = ghostMulDivUp(ghostMulDivUp(seizedAssets, price0, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    require seizedAssets > 0;
    require to_mathint(seizedAssets) <= to_mathint(collat0), "seize fits collateral[0] (L669)";
    require repaidUnits <= maxRepaid, "derived repaidUnits: RCF check passes (L661)";
    require repaidUnits <= debtAfter, "derived repaidUnits: no debt underflow (L675)";

    bytes data;
    liquidate@withrevert(e, market, 0, seizedAssets, 0, borrower, false, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// Seize path, post-maturity: no RCF. lif >= WAD, and the derived repaidUnits = mulDivUp(quote, WAD, lif) is
/// largest at lif = WAD (mulDivUp is antitone in its denominator), so it is upper-bounded by `quote` itself.
rule seizePostMaturityLiquidatableForAnySafeAmount(env e, Midnight.Market market, address borrower, address receiver, uint256 seizedAssets) {
    bytes32 id = summaryToId(market);
    seizablePreamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity partition (liquidatable by expiry)";

    uint128 collat0 = collateral(id, borrower, 0);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 _debt = debtOf(id, borrower);
    mathint debtAfter = debtAfterBadDebt(market, id, borrower);

    mathint quoteUp = ghostMulDivUp(seizedAssets, price0, ORACLE_PRICE_SCALE());

    require seizedAssets > 0;
    require to_mathint(seizedAssets) <= to_mathint(collat0), "seize fits collateral[0] (L669)";
    require quoteUp <= debtAfter, "derived repaidUnits (<= quote since lif >= WAD): no debt underflow (L675)";

    bytes data;
    liquidate@withrevert(e, market, 0, seizedAssets, 0, borrower, true, receiver, 0, data);
    assert !lastReverted, "the call is live (succeeds)";
    assert to_mathint(debtOf(id, borrower)) < to_mathint(_debt), "and it makes progress: debt strictly decreases";
}

/// BAD-DEBT WITNESS (repaidUnits = 0, seizedAssets = 0): any liquidatable borrower can be liquidated with the
/// no-transfer call, which skips the seize/RCF/underflow block entirely (never reverts, any collateral state).
/// Covers the borrowers the seizing rules cannot (dust / inactive collateral 0). No progress assert: a 0/0 call
/// only realizes bad debt, which may be zero. ///
rule badDebtCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver, bool postMaturityMode) {
    bytes32 id = summaryToId(market);
    threeCollatSetup(e, market, id, borrower);

    require postMaturityMode ? e.block.timestamp > market.maturity : !isHealthy(market, id, borrower), "borrower is liquidatable in the chosen mode";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, postMaturityMode, receiver, 0, data);
    assert !lastReverted, "the no-transfer bad-debt call is live (succeeds)";
}
