// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function _.price() external => NONDET;

    // Summarize internals irrelevant to credit and debt tracking.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// HELPERS ///

// Under noSlash, all mulDiv calls in _updatePosition hit y == d (identity) or y == 0.
function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    uint256 res;
    return res;
}

// All rules in this file assume no accrual and no slash.
definition noAccrual(env e, bytes32 id, address user) returns bool = currentContract.position[id][user].pendingFee == 0 || e.block.timestamp == currentContract.position[id][user].lastAccrual;

definition noSlash(bytes32 id, address user) returns bool = currentContract.position[id][user].lossIndex == currentContract.obligationState[id].lossIndex && currentContract.position[id][user].lossIndex < max_uint128;

/// REPAY ///

/// Repay decreases onBehalf's debt by exactly units and only changes position[id][onBehalf].debt
rule repayEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    repay(e, obligation, units, onBehalf);

    assert debtOf(id, onBehalf) == debtBefore - units;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != onBehalf || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// WITHDRAW ///

/// When no slash or accrual occurs, withdraw decreases onBehalf's credit by exactly units
/// and only changes position[id][onBehalf].
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    require noSlash(id, onBehalf);
    require noAccrual(e, id, onBehalf);

    uint256 creditBefore = creditOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    withdraw(e, obligation, units, onBehalf, receiver);

    assert creditOf(id, onBehalf) == creditBefore - units;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyUser != onBehalf || anyId != id => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// TAKE ///

/// When no slash or accrual occurs, take changes maker's and taker's net credit-debt by +/- units
/// and only changes credit and debt of maker and taker at the obligation id.
rule takeEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);
    require noSlash(id, offer.maker);
    require noSlash(id, taker);
    require noAccrual(e, id, offer.maker);
    require noAccrual(e, id, taker);

    mathint makerNetBefore = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetBefore = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    mathint makerNetAfter = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetAfter = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));

    mathint makerDelta = offer.buy ? units : -units;
    assert makerNetAfter == makerNetBefore + makerDelta;
    mathint takerDelta = offer.buy ? -units : units;
    assert takerNetAfter == takerNetBefore + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => creditOf(anyId, anyUser) == otherCreditBefore && debtOf(anyId, anyUser) == otherDebtBefore;
}

/// LIQUIDATE ///

/// When no fee accrual occurs, liquidate decreases the borrower's debt by at least repaidUnits,
/// and only changes position[id][borrower].debt.
rule liquidateEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, borrower);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert debtOf(id, borrower) <= debtBefore - repaidResult;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != borrower || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// SLASH AND ACCRUE ///

/// When no slash or accrual occurs, updatePosition does not change credit or debt.
rule updatePositionEffects(env e, Midnight.Obligation obligation, address user, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    require noSlash(id, user);
    require noAccrual(e, id, user);

    uint256 creditBefore = creditOf(id, user);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    updatePosition(e, obligation, user);

    assert creditOf(id, user) == creditBefore;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyUser != user || anyId != id => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, updatePosition, and withdrawCollateral do not change any user's credit or debt.
rule creditAndDebtUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:updatePosition(Midnight.Obligation, address).selector
} {
    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    assert creditOf(id, user) == creditBefore;
    assert debtOf(id, user) == debtBefore;
}

/// SUPPLY COLLATERAL ///

/// supplyCollateral increases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule supplyCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);

    assert collateralOf(id, onBehalf, collateralIndex) == collateralBefore + assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// WITHDRAW COLLATERAL ///

/// withdrawCollateral decreases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule withdrawCollateralCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);

    assert collateralOf(id, onBehalf, collateralIndex) == collateralBefore - assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// LIQUIDATE (COLLATERAL) ///

/// liquidate decreases the borrower's collateral at collateralIndex by exactly seizedResult,
/// and only changes position[id][borrower].collateral[collateralIndex].
rule liquidateCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, borrower, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    uint256 seizedResult;
    seizedResult, _ = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert collateralOf(id, borrower, collateralIndex) == collateralBefore - seizedResult;
    assert anyUser != borrower || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// ALL OTHER FUNCTIONS (COLLATERAL) ///

/// Functions other than supplyCollateral, withdrawCollateral, and liquidate do not change any user's collateral.
rule collateralUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user, uint256 colIdx)
filtered {
    f -> !f.isView
        && f.selector != sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
} {
    uint256 collateralBefore = collateralOf(id, user, colIdx);
    f(e, args);
    assert collateralOf(id, user, colIdx) == collateralBefore;
}
