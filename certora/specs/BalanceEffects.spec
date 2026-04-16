// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function _.price() external => NONDET;

    // Summarize internals irrelevant to credit and debt tracking.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
}

/// UPDATE POSITION ///

/// updatePosition sets user's credit to the post-update value,
/// only changes credit of user at the obligation id, and accrues fee to continuousFeeCredit.
rule updatePositionEffects(env e, Midnight.Obligation obligation, address user, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, obligation, id, user);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeAmountBefore = continuousFeeCredit(id);

    updatePosition(e, obligation, user);

    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != user) => creditOf(anyId, anyUser) == anyCredit;
    assert creditOf(id, user) == updatedUserCredit;
    assert continuousFeeCredit(id) == feeAmountBefore + userFee;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-update credit by exactly units
/// and only changes credit of onBehalf at the obligation id.
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, obligation, id, onBehalf);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeAmountBefore = continuousFeeCredit(id);

    withdraw(e, obligation, units, onBehalf, receiver);

    assert creditOf(id, onBehalf) == updatedUserCredit - units;
    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != onBehalf) => creditOf(anyId, anyUser) == anyCredit;
    assert continuousFeeCredit(id) == feeAmountBefore + userFee;
}

/// TAKE ///

/// take changes maker's and taker's net credit-debt by +/- units relative to their post-update values
/// and only changes credit of maker and taker and debt of maker and taker at the obligation id.
rule takeEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);

    uint128 makerCreditBefore;
    makerCreditBefore, _, _ = updatePositionView(e, offer.obligation, id, offer.maker);
    uint128 takerCreditBefore;
    takerCreditBefore, _, _ = updatePositionView(e, offer.obligation, id, taker);
    mathint makerNetBefore = to_mathint(makerCreditBefore) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetBefore = to_mathint(takerCreditBefore) - to_mathint(debtOf(id, taker));
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    mathint makerNetAfter = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetAfter = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));

    mathint makerDelta = offer.buy ? units : -units;
    assert makerNetAfter == makerNetBefore + makerDelta;
    mathint takerDelta = offer.buy ? -units : units;
    assert takerNetAfter == takerNetBefore + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// REPAY ///

/// Repay decreases onBehalf's debt by exactly units and only changes position[id][onBehalf].debt
rule repayEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    repay(e, obligation, units, onBehalf, data);

    assert debtOf(id, onBehalf) == debtBefore - units;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != onBehalf || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// LIQUIDATE ///

/// Liquidate decreases the borrower's debt by at least repaidUnits,
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

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, updatePosition, and withdrawCollateral do not change any user's credit or debt.
rule creditAndDebtUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address, bytes).selector
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

    uint256 collateralBefore = collateral(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);

    assert collateral(id, onBehalf, collateralIndex) == collateralBefore + assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// WITHDRAW COLLATERAL ///

/// withdrawCollateral decreases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule withdrawCollateralCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateral(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);

    assert collateral(id, onBehalf, collateralIndex) == collateralBefore - assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// LIQUIDATE (COLLATERAL) ///

/// liquidate decreases the borrower's collateral at collateralIndex by exactly seizedResult,
/// and only changes position[id][borrower].collateral[collateralIndex].
rule liquidateCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateral(id, borrower, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    uint256 seizedResult;
    seizedResult, _ = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert collateral(id, borrower, collateralIndex) == collateralBefore - seizedResult;
    assert anyUser != borrower || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
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
    uint256 collateralBefore = collateral(id, user, colIdx);
    f(e, args);
    assert collateral(id, user, colIdx) == collateralBefore;
}
