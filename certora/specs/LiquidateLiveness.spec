// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired."

Existential liveness: for every liquidatable borrower, there exists a `liquidate`
call that succeeds. Witness in all rules: `repaidUnits = 1`, `seizedAssets = 0`,
`collateralIndex = 0`, `callback = 0`.

Partitions (the liquidatability condition is `unhealthy || timestamp > maturity`):
- postMaturityCanBeLiquidated: `healthyPath = true`, `timestamp > maturity`. RCF skipped.
- unhealthyLltvFullCanBeLiquidated: `healthyPath = false`, `lltv[0] == WAD`. RCF maxRepaid
  collapses to `type(uint256).max` (L657), so the RCF check passes unconditionally.
- unhealthyLowLltvCanBeLiquidated: `healthyPath = false`, `lltv[0] < WAD`. Uses the
  extra `b >= d => mulDivUp(a,b,d) >= a` axiom (mirror of the existing mulDivDown axiom)
  combined with `validCollateralAt`'s `lltv*maxLif <= WAD*(WAD-1)` to show maxRepaid >= 1.
- unhealthyCanBeLiquidated: `healthyPath = false`, any lltv, in markets where the
  `rcfThreshold` escape hatch holds. Subsumed by unhealthyLowLltvCanBeLiquidated when
  lltv < WAD; kept for the alternative reasoning path.

Modeling assumptions (cf. LIVENESS section of Midnight.sol):
- 2-collateral market with both bits activated (loop_iter = 2 constraint).
- `market.liquidatorGate == 0` (no gate vetoes the liquidation).
- `e.msg.value == 0` (liquidate is non-payable).
- `SafeTransferLib.safeTransfer*` summarized as NONDET (tokens never revert on transfer).
- Oracle prices via a non-reverting persistent ghost (oracles do not revert nor return 0
  for collateral 0; price > 0 is forced by the preamble's seize bound).
- Borrower has `debt > 0` and is not transiently liquidation-locked (tx-start convention).
- Invariants from Midnight.spec assumed in preamble: `totalUnits == sumDebt + withdrawable`
  (gives `totalUnits >= debt` and `withdrawable + debt <= MAX_UINT128`).
- `validCollateralAt` per-collateral bounds (protocol-enforced by touchMarket).
*/

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
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
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivUp(a, b, d) <= a;

    /// Mirror of ghostMulDivDown's `b <= d => <= a` axiom. Sound: result * d >= a*b >= a*d.
    /// Needed by unhealthyLowLltvCanBeLiquidated to derive maxRepaid >= debt - maxDebt >= 1.
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b >= d => ghostMulDivUp(a, b, d) >= a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(a, d, d) == a;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(0, a, d) == 0 && ghostMulDivUp(a, 0, d) == 0;
    axiom forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 && a1 <= a2 => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d);
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

/// Shared preamble: 2-collateral market with both bits activated, well-behaved env,
/// unlocked, positive debt, and the liveness bound on collateral 0 that absorbs the
/// 1-unit seizure at lif = maxLif.
function preamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 2, "two-collateral market";
    require collateralBitmap(id, borrower) == 3, "both collateral bits activated";
    require summaryGetBit(3, 0) && summaryGetBit(3, 1), "bitmap=3: bits 0,1 set";
    require forall uint256 i. i >= 2 => !summaryGetBit(3, i), "bitmap=3: no other bits set";

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);

    require e.msg.value == 0, "liquidate is non-payable";
    require market.liquidatorGate == 0, "no liquidator gate (LIVENESS)";
    require e.block.timestamp < MAX_TIMESTAMP(), "timestamp fits in uint64";
    require market.maturity < MAX_TIMESTAMP(), "maturity fits in uint64";

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt, "from totalUnitsEqualsSumNegativeDebtPlusWithdrawable (Midnight.spec)";
    require to_mathint(withdrawable(id)) + to_mathint(_debt) <= MAX_UINT128(), "from totalUnitsEqualsSumNegativeDebtPlusWithdrawable (Midnight.spec)";
    require !liquidationLocked(id, borrower), "transient lock is zero at tx start";
    require _debt > 0, "borrower has debt";

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    require maxLif * ORACLE_PRICE_SCALE() <= collat * WAD() * summaryPrice(oracle), "1-unit seize fits in collat[0] (also forces price[0]>0)";
}

/// Post-maturity: healthyPath = true. RCF skipped, no lltv split needed.
rule postMaturityCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity, "post-maturity partition";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

/// Unhealthy, lltv == WAD: healthyPath = false.
/// RCF maxRepaid = type(uint256).max, so the check passes without any precondition on rcfThreshold.
rule unhealthyLltvFullCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require !isHealthy(market, id, borrower), "unhealthy partition";
    require market.collateralParams[0].lltv == WAD(), "lltv == WAD partition (maxRepaid = uint256.max)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// Unhealthy, lltv < WAD: healthyPath = false.
/// Sound scaffolding lemmas help the solver with NIA chains (bad-debt path, RCF denominator).
rule unhealthyLowLltvCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    uint256 lltv = market.collateralParams[0].lltv;
    require lltv < WAD(), "lltv < WAD partition";

    // (a) Direct maxDebt computation (avoids isHealthy's loop/liquidate commutativity).
    uint256 maxLif = market.collateralParams[0].maxLif;
    uint256 lltv1 = market.collateralParams[1].lltv;
    uint128 collat0 = collateral(id, borrower, 0);
    uint128 collat1 = collateral(id, borrower, 1);
    uint256 price0 = summaryPrice(market.collateralParams[0].oracle);
    uint256 price1 = summaryPrice(market.collateralParams[1].oracle);
    mathint maxDebt = to_mathint(ghostMulDivDown(ghostMulDivDown(collat0, price0, ORACLE_PRICE_SCALE()), lltv, WAD())) + to_mathint(ghostMulDivDown(ghostMulDivDown(collat1, price1, ORACLE_PRICE_SCALE()), lltv1, WAD()));
    uint256 _debt = debtOf(id, borrower);
    require to_mathint(_debt) > maxDebt, "unhealthy: debt > maxDebt (replaces isHealthy)";

    // (b) inner := mulDivUp(maxLif, lltv, WAD) <= WAD - 1 (from validCollateralAt + axiom 2).
    require to_mathint(ghostMulDivUp(maxLif, lltv, WAD())) <= to_mathint(WAD()) - 1, "lemma: mulDivUp(maxLif, lltv, WAD) <= WAD - 1 (from validCollateralAt + axiom 2)";

    // (c) WAD - inner >= 1 (maxRepaid denominator is positive, from (b)).
    require to_mathint(WAD()) - to_mathint(ghostMulDivUp(maxLif, lltv, WAD())) >= 1, "from (b): WAD - inner >= 1";

    // (d) Per-collateral recovery > maxDebt contribution (from lltv*maxLif < WAD^2 + ghost axioms).
    //     Bridges the bad-debt path: ensures _position.debt > maxDebt after bad-debt realization.
    uint256 maxLif1 = market.collateralParams[1].maxLif;
    require to_mathint(ghostMulDivUp(ghostMulDivUp(collat0, price0, ORACLE_PRICE_SCALE()), WAD(), maxLif)) > to_mathint(ghostMulDivDown(ghostMulDivDown(collat0, price0, ORACLE_PRICE_SCALE()), lltv, WAD())), "lemma: recovery[0] > maxDebtContrib[0] (from lltv*maxLif < WAD^2, collat0*price0 > 0)";
    require to_mathint(ghostMulDivUp(ghostMulDivUp(collat1, price1, ORACLE_PRICE_SCALE()), WAD(), maxLif1)) >= to_mathint(ghostMulDivDown(ghostMulDivDown(collat1, price1, ORACLE_PRICE_SCALE()), lltv1, WAD())), "lemma: recovery[1] >= maxDebtContrib[1] (from lltv1*maxLif1 <= WAD^2)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// Unhealthy, any lltv: healthyPath = false.
/// The rcfThreshold escape hatch makes the second disjunct hold, sidestepping the nonlinear maxRepaid.
/// Subsumed by unhealthyLowLltvCanBeLiquidated for lltv < WAD and by unhealthyLltvFullCanBeLiquidated
/// for lltv == WAD; kept as an alternative proof using the second RCF disjunct.
rule unhealthyCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require !isHealthy(market, id, borrower), "unhealthy partition";

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;

    /// Sufficient arithmetic bound for `rcfThreshold > mulDivUp(mulDivUp(collat, price, OPS), WAD, maxLif)`,
    /// derived from the two mulDivUp ceiling axioms.
    require to_mathint(market.rcfThreshold) * to_mathint(maxLif) * to_mathint(ORACLE_PRICE_SCALE()) > to_mathint(collat) * to_mathint(summaryPrice(oracle)) * to_mathint(WAD()) + (to_mathint(ORACLE_PRICE_SCALE()) - 1) * to_mathint(WAD()) + (to_mathint(maxLif) - 1) * to_mathint(ORACLE_PRICE_SCALE()), "rcfThreshold escape: ceiling-bound on mulDivUp(mulDivUp(collat,price,OPS),WAD,maxLif)";

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}
