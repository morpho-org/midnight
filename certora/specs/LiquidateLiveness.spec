// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired" — full strength.

For every liquidatable borrower and every amount in the safe interval an off-chain liquidator would compute,
`liquidate` (1) does not revert and (2) strictly decreases the borrower's debt.
Covers both modes (unhealthy lltv == WAD / lltv < WAD, post-maturity) and both entry paths (repay: parametric
repaidUnits; seize: parametric seizedAssets). Dust / inactive-collateral-0 borrowers (a seizing call would
divide by a zero price) are instead covered by the no-transfer bad-debt witness `badDebtCanBeLiquidated` (0/0).

The safe interval is reconstructed in CVL from the contract's own intermediates; since mulDiv* are deterministic
ghosts the values match `liquidate` exactly, and each bound neutralises one revert site:
  amount <= maxRepaid => RCF passes (L661);   amount <= debtAfter => debt sub no underflow (L675);
  seize(amount) <= collateral[0] => collateral sub no underflow (L669);   debtAfter >= maxDebt => L659 ok.
The amount only touches the seized collateral 0; the other collaterals add only the amount-independent
maxDebt/badDebt sums (which vanish when they are inactive).

Soundness: over-constraining the interval only weakens liveness (never unsound); under-constraining surfaces as
an !lastReverted counterexample, so the bounds need only be non-vacuous (basic sanity), not exactly tight. The
scaffolding `require`s (lowLltvScaffolding) are deterministic consequences of the mulDiv* ghost axioms and the
validCollateralAt bounds, justified inline at each require.

Scope: a NUM_COLLATERALS-collateral market with up to NUM_COLLATERALS active collaterals, bounded by loop_iter.

Assumptions (LIVENESS): no liquidator gate, well-behaved tokens (transfers summarized NONDET, i.e. non-reverting),
and oracle prices constant per address. The deterministic `mulDiv*` ghost summaries, the per-collateral validity
assumptions (`validCollateralAt`, as enforced by `touchMarket` at market creation), and the bitmap/collateral
coupling invariant are defined below.
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

definition NUM_COLLATERALS() returns uint256 = 3;

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

/// Shared setup for any liquidatable borrower in an N-collateral market: at most collaterals 0..N-1 active (so
/// the liquidate loop runs <= loop_iter times), well-behaved env, no liquidator gate, unlocked, positive debt,
/// and the totalUnits/withdrawable bounds imported from Midnight.spec. Does NOT assume which collateral is active.
function multiCollatSetup(env e, Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == NUM_COLLATERALS(), "N-collateral market";
    uint128 bitmap = collateralBitmap(id, borrower);
    require forall uint256 i. i >= NUM_COLLATERALS() => !summaryGetBit(bitmap, i), "at most collaterals 0..N-1 active (<= loop_iter)";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);
    validCollateralAt(market, id, borrower, 2);

    require e.msg.value == 0, "liquidate is non-payable";
    require market.liquidatorGate == 0, "no liquidator gate (LIVENESS)";
    require e.block.timestamp < MAX_TIMESTAMP(), "timestamp fits in uint64";
    require market.maturity < MAX_TIMESTAMP(), "maturity fits in uint64";

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt, "totalUnits = sumDebt + withdrawable >= this borrower's debt (Midnight.spec)";
    require to_mathint(withdrawable(id)) + to_mathint(_debt) <= MAX_UINT128(), "withdrawable + debt <= totalUnits <= uint128 max (Midnight.spec)";
    require !liquidationLocked(id, borrower), "transient lock is zero at tx start";
    require _debt > 0, "borrower has debt";

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 2);
}

/// Extends multiCollatSetup for the seizing rules: collateral 0 (the seized one) is active and large enough to
/// absorb the seizure. The magnitude bound (which also forces price0 > 0) is exactly the hypothesis behind the
/// strict recovery0 > contrib0 fact assumed in lowLltvScaffolding. Dust/inactive collateral 0 is covered instead
/// by badDebtCanBeLiquidated.
function seizablePreamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    multiCollatSetup(e, market, id, borrower);
    require summaryGetBit(collateralBitmap(id, borrower), 0), "collateral 0 (the seized collateral) is active";
    require market.collateralParams[0].maxLif * ORACLE_PRICE_SCALE() <= collateral(id, borrower, 0) * WAD() * summaryPrice(market.collateralParams[0].oracle), "collateral 0 is non-dust & priced (forces price0 > 0; gives strict recovery0 > contrib0)";
}

/// Per-collateral maxDebt contribution (down-rounded) and recovery (the bad-debt offset). Both vanish when the
/// collateral is inactive (collat == 0 by nonZeroCollateralsAreActivated).
function contribAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) returns mathint {
    return ghostMulDivDown(ghostMulDivDown(collateral(id, borrower, i), summaryPrice(market.collateralParams[i].oracle), ORACLE_PRICE_SCALE()), market.collateralParams[i].lltv, WAD());
}

function recoveryAt(Midnight.Market market, bytes32 id, address borrower, uint256 i) returns mathint {
    return ghostMulDivUp(ghostMulDivUp(collateral(id, borrower, i), summaryPrice(market.collateralParams[i].oracle), ORACLE_PRICE_SCALE()), WAD(), market.collateralParams[i].maxLif);
}

/// maxDebt = sum over all collaterals of the down-rounded contribution.
function maxDebtSum(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    return contribAt(market, id, borrower, 0) + contribAt(market, id, borrower, 1) + contribAt(market, id, borrower, 2);
}

/// debtAfter = debt - badDebt, where badDebt = zeroFloorSub chain = max(0, debt - sum of recoveries).
function debtAfterBadDebt(Midnight.Market market, bytes32 id, address borrower) returns mathint {
    mathint rec = recoveryAt(market, id, borrower, 0) + recoveryAt(market, id, borrower, 1) + recoveryAt(market, id, borrower, 2);
    mathint _debt = debtOf(id, borrower);
    mathint badDebt = _debt > rec ? _debt - rec : 0;
    return _debt - badDebt;
}

/// Assumes the three arithmetic facts the lltv < WAD maxRepaid computation relies on. Each is a deterministic
/// consequence of the mulDiv* ghost axioms and the validCollateralAt bounds (themselves enforced by touchMarket
/// at market creation), so requiring them is sound: they hold on every valid Midnight market state.
function lowLltvScaffolding(Midnight.Market market, bytes32 id, address borrower) {
    uint256 lltv0 = market.collateralParams[0].lltv;
    uint256 maxLif0 = market.collateralParams[0].maxLif;

    // mulDivUp(maxLif, lltv, WAD) = ceil(maxLif*lltv / WAD) <= ceil(WAD*(WAD-1) / WAD) = WAD - 1, since
    // validCollateralAt gives lltv*maxLif <= WAD*(WAD-1) when lltv < WAD (touchMarket only accepts
    // maxLif = maxLif(lltv, cursor), which satisfies the ExactMath bound). So the maxRepaid denominator
    // WAD - mulDivUp(lif, lltv, WAD) >= 1 (no zero/underflow at Midnight.sol's `WAD - lif.mulDivUp(lltv, WAD)`).
    require to_mathint(ghostMulDivUp(maxLif0, lltv0, WAD())) <= to_mathint(WAD()) - 1, "WAD*(WAD-1) ExactMath bound (touchMarket) => inner <= WAD-1";

    // recovery_i = ceil(ceil(collat*price/SCALE) * WAD / maxLif) and contrib_i = floor(floor(collat*price/SCALE) *
    // lltv / WAD) quote the same collateral; recovery scales by WAD/maxLif and contribution by lltv/WAD. Because
    // lltv*maxLif <= WAD*(WAD-1) < WAD^2 (validCollateralAt), WAD/maxLif > lltv/WAD, and the up/down rounding only
    // widens the gap. For the seized collateral 0 the non-dust preamble bound forces the quote >= 1 (strictly
    // positive), so the inequality is strict; this is what makes debtAfter > maxDebt and thus maxRepaid >= 1
    // (non-vacuous interval). For collaterals 1 and 2 the same comparison holds non-strictly, and trivially as
    // 0 >= 0 when the collateral is inactive (collat == 0 by nonZeroCollateralsAreActivated).
    require recoveryAt(market, id, borrower, 0) > contribAt(market, id, borrower, 0), "non-dust collat0, WAD/maxLif > lltv/WAD (lltv*maxLif < WAD^2) => recovery0 strictly > contrib0";
    require recoveryAt(market, id, borrower, 1) >= contribAt(market, id, borrower, 1), "WAD/maxLif >= lltv/WAD (lltv*maxLif <= WAD^2) => recovery1 >= contrib1 (0 >= 0 if inactive)";
    require recoveryAt(market, id, borrower, 2) >= contribAt(market, id, borrower, 2), "WAD/maxLif >= lltv/WAD (lltv*maxLif <= WAD^2) => recovery2 >= contrib2 (0 >= 0 if inactive)";
}

/// INVARIANT ///

// Proven in CollateralBitmap.spec; assumed here via requireInvariant (not re-proven in this spec).
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

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

    // maxRepaid as computed by the contract (L658-660): (debtAfter - maxDebt) ceil-div (WAD - lif*lltv/WAD),
    // using the seized collateral 0's lltv/lif. debtAfter >= maxDebt from the scaffolding facts.
    mathint inner = ghostMulDivUp(maxLif, lltv, WAD());
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), WAD(), assert_uint256(to_mathint(WAD()) - inner));

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

/// SEIZE PATH (seizedAssets > 0, repaidUnits = 0) ///
/// The liquidator specifies the collateral to seize; the contract derives repaidUnits (L650):
/// repaidUnits = mulDivUp(mulDivUp(seizedAssets, price0, ORACLE_PRICE_SCALE), WAD, lif). The collateral underflow
/// guard is a direct `seizedAssets <= collateral[0]`; debt-underflow and RCF apply to the derived repaidUnits.
/// seizedAssets > 0 and price0 > 0 force derived repaidUnits >= 1, so progress still holds.

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

/// Seize path, unhealthy, lltv < WAD: RCF caps the derived repaidUnits by maxRepaid; same scaffolding facts apply.
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

    mathint inner = ghostMulDivUp(maxLif, lltv, WAD());
    mathint maxRepaid = ghostMulDivUp(assert_uint256(debtAfter - maxDebt), WAD(), assert_uint256(to_mathint(WAD()) - inner));

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

/// BAD-DEBT WITNESS (repaidUnits = 0, seizedAssets = 0) ///

/// Any liquidatable borrower (unhealthy or expired) can be liquidated with the no-transfer call
/// repaidUnits = 0, seizedAssets = 0. This path skips the seize/RCF/underflow block entirely, so it never
/// reverts regardless of collateral magnitude or which collateral is active. It covers the borrowers the
/// seizing rules cannot: dust collateral 0, and borrowers whose collateral 0 is inactive (where a seizing call
/// would divide by a zero liquidatedCollatPrice). No progress assert: a 0/0 call only realizes bad debt, which
/// may be zero (so the debt need not strictly decrease).
rule badDebtCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver, bool postMaturityMode) {
    bytes32 id = summaryToId(market);
    multiCollatSetup(e, market, id, borrower);

    require postMaturityMode ? e.block.timestamp > market.maturity : !isHealthy(market, id, borrower), "borrower is liquidatable in the chosen mode";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, postMaturityMode, receiver, 0, data);
    assert !lastReverted, "the no-transfer bad-debt call is live (succeeds)";
}
