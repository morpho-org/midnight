// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

/**
Property: "Debts can always be liquidated if unhealthy or expired."

Existential liveness: for every liquidatable borrower, there exists a `liquidate`
call that succeeds. Witness in all rules: `repaidUnits = 1`.

- postMaturityCanBeLiquidated: `healthyPath = true` covers all `timestamp > maturity`.
  RCF is skipped.

- unhealthyLltvFullCanBeLiquidated: `healthyPath = false`, `lltv == WAD`. RCF maxRepaid
  collapses to `type(uint256).max` (L656), so the RCF check passes unconditionally.

- unhealthyCanBeLiquidated: `healthyPath = false`, any lltv. Uses the `rcfThreshold`
  escape hatch (second disjunct of L659-660) to sidestep the nonlinear `maxRepaid`.

Together they cover the property except for: unhealthy borrowers with `lltv < WAD`
in a market where the `rcfThreshold` escape hatch does not hold. That partition
requires reasoning about the nonlinear `maxRepaid` formula at L655 and is the
acknowledged limit of this proof.
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

    require lltv > 0 && lltv <= WAD();
    require maxLif >= WAD();
    require lltv < WAD() => to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * (to_mathint(WAD()) - 1);
    require to_mathint(lltv) * to_mathint(maxLif) <= to_mathint(WAD()) * to_mathint(WAD());

    address oracle = market.collateralParams[i].oracle;
    require to_mathint(collateral(id, borrower, i)) * to_mathint(summaryPrice(oracle))
            <= to_mathint(ORACLE_PRICE_SCALE()) * to_mathint(WAD()) * MAX_UINT128();
}

/// Shared preamble: 2-collateral market with both bits activated, well-behaved env,
/// unlocked, positive debt, and the liveness bound on collateral 0 that absorbs the
/// 1-unit seizure at lif = maxLif.
function preamble(env e, Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length == 2;
    require collateralBitmap(id, borrower) == 3;
    require summaryGetBit(3, 0) && summaryGetBit(3, 1);
    require forall uint256 i. i >= 2 => !summaryGetBit(3, i);

    validCollateralAt(market, id, borrower, 0);
    validCollateralAt(market, id, borrower, 1);

    require e.msg.value == 0;
    require market.liquidatorGate == 0;
    require e.block.timestamp < MAX_TIMESTAMP();
    require market.maturity < MAX_TIMESTAMP();

    uint256 _debt = debtOf(id, borrower);
    require totalUnits(id) >= _debt;
    require to_mathint(withdrawable(id)) + to_mathint(_debt) <= MAX_UINT128();
    require !liquidationLocked(id, borrower);
    require _debt > 0;

    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    require maxLif * ORACLE_PRICE_SCALE() <= collat * WAD() * summaryPrice(oracle);
}

/// Post-maturity: healthyPath = true. RCF skipped, no lltv split needed.
rule postMaturityCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require e.block.timestamp > market.maturity;

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, true, receiver, 0, data);
    assert !lastReverted;
}

/// Unhealthy, lltv == WAD: healthyPath = false. RCF maxRepaid = type(uint256).max
/// (L656), so the check passes without any precondition on rcfThreshold.
rule unhealthyLltvFullCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require !isHealthy(market, id, borrower);
    require market.collateralParams[0].lltv == WAD();

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}

/// Unhealthy, any lltv: healthyPath = false. The rcfThreshold escape hatch makes
/// the second disjunct of L659-660 hold, sidestepping the nonlinear maxRepaid at L655.
rule unhealthyCanBeLiquidated(env e, Midnight.Market market, address borrower, address receiver) {
    bytes32 id = summaryToId(market);
    preamble(e, market, id, borrower);

    require !isHealthy(market, id, borrower);

    address oracle = market.collateralParams[0].oracle;
    uint128 collat = collateral(id, borrower, 0);
    uint256 maxLif = market.collateralParams[0].maxLif;
    uint256 step1 = summaryMulDivUp(collat, summaryPrice(oracle), ORACLE_PRICE_SCALE());
    uint256 collatValueOverLif = summaryMulDivUp(step1, WAD(), maxLif);
    require market.rcfThreshold > collatValueOverLif;

    bytes data;
    liquidate@withrevert(e, market, 0, 0, 1, borrower, false, receiver, 0, data);
    assert !lastReverted;
}
