// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;

    // Summarize internals irrelevant to credit and debt tracking.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address[], uint256[], bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
}

/// UPDATE POSITION ///

/// updatePosition can only decrease user's credit (through slashing and fee accrual),
/// sets it to the post-update value, only changes credit of user at the market id,
/// and accrues fee to continuousFeeCredit.
rule updatePositionEffects(env e, Midnight.Market market, address user, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, market);

    uint256 creditBefore = creditOf(id, user);
    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, market, id, user);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeAmountBefore = continuousFeeCredit(id);

    updatePosition(e, market, user);

    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != user) => creditOf(anyId, anyUser) == anyCredit;
    assert creditOf(id, user) == updatedUserCredit;
    assert continuousFeeCredit(id) == feeAmountBefore + userFee;
    assert creditOf(id, user) <= creditBefore;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-update credit by exactly units
/// and only changes credit of onBehalf at the market id.
rule withdrawEffects(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, market);

    uint128 updatedUserCredit;
    uint128 userFee;
    updatedUserCredit, _, userFee = updatePositionView(e, market, id, onBehalf);

    uint256 anyCredit = creditOf(anyId, anyUser);
    uint256 anyDebt = debtOf(anyId, anyUser);
    uint256 feeAmountBefore = continuousFeeCredit(id);

    withdraw(e, market, units, onBehalf, receiver);

    assert creditOf(id, onBehalf) == updatedUserCredit - units;
    assert debtOf(anyId, anyUser) == anyDebt;
    assert (anyId != id) || (anyUser != onBehalf) => creditOf(anyId, anyUser) == anyCredit;
    assert continuousFeeCredit(id) == feeAmountBefore + userFee;
}

/// TAKE ///

/// take changes maker's and taker's net credit-debt by +/- units relative to their post-update values
/// and only changes credit of maker and taker and debt of maker and taker at the market id.
rule takeEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.market);

    uint128 makerCreditBefore;
    makerCreditBefore, _, _ = updatePositionView(e, offer.market, id, offer.maker);
    uint128 takerCreditBefore;
    takerCreditBefore, _, _ = updatePositionView(e, offer.market, id, taker);
    mathint makerNetBefore = to_mathint(makerCreditBefore) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetBefore = to_mathint(takerCreditBefore) - to_mathint(debtOf(id, taker));
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    mathint makerNetAfter = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerNetAfter = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));

    mathint makerDelta = offer.buy ? units : -units;
    assert makerNetAfter == makerNetBefore + makerDelta;
    mathint takerDelta = offer.buy ? -units : units;
    assert takerNetAfter == takerNetBefore + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// The buyer side cannot newly become a borrower: buyer's debt is non-increasing. If buyer's credit increased, then buyer's debt is zero after the take.
/// Buyer's credit is non-decreasing relative to its post-update value and can increase by at most take units.
/// Buyer's debt is non-increasing and can decrease by at most take units.
rule takeBuyerEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData) {
    bytes32 id = toId(e, offer.market);

    address buyer = offer.buy ? offer.maker : taker;
    uint256 buyerDebtBefore = debtOf(id, buyer);
    uint128 buyerUpdatedCreditBefore;
    buyerUpdatedCreditBefore, _, _ = updatePositionView(e, offer.market, id, buyer);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    assert creditOf(id, buyer) > buyerUpdatedCreditBefore => debtOf(id, buyer) == 0;
    assert creditOf(id, buyer) >= buyerUpdatedCreditBefore;
    assert creditOf(id, buyer) <= buyerUpdatedCreditBefore + units;
    assert debtOf(id, buyer) <= buyerDebtBefore;
    assert debtOf(id, buyer) >= buyerDebtBefore - units;
}

/// The seller side cannot newly become a lender: seller's credit is non-increasing relative to its post-update value. If seller's debt increased, then seller's credit is zero after the take.
/// Seller's debt is non-decreasing, and can increase by at most take units.
/// Seller's credit is non-increasing relative to its post-update value and can decrease by at most take units.
rule takeSellerEffects(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData) {
    bytes32 id = toId(e, offer.market);

    address seller = offer.buy ? taker : offer.maker;
    uint256 sellerDebtBefore = debtOf(id, seller);
    uint128 sellerUpdatedCreditBefore;
    sellerUpdatedCreditBefore, _, _ = updatePositionView(e, offer.market, id, seller);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    assert debtOf(id, seller) > sellerDebtBefore => creditOf(id, seller) == 0;
    assert debtOf(id, seller) >= sellerDebtBefore;
    assert debtOf(id, seller) <= sellerDebtBefore + units;
    assert creditOf(id, seller) <= sellerUpdatedCreditBefore;
    assert creditOf(id, seller) >= sellerUpdatedCreditBefore - units;
}

/// REPAY ///

/// Repay decreases onBehalf's debt by exactly units and only changes position[id][onBehalf].debt
rule repayEffects(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, market);

    uint256 debtBefore = debtOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    repay(e, market, units, onBehalf, callback, data);

    assert debtOf(id, onBehalf) == debtBefore - units;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != onBehalf || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// LIQUIDATE ///

/// Liquidate decreases the borrower's debt by at least repaidUnits,
/// and only changes position[id][borrower].debt.
rule liquidateEffects(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, market);

    uint256 debtBefore = debtOf(id, borrower);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    assert debtOf(id, borrower) <= debtBefore - repaidResult;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != borrower || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, updatePosition, and withdrawCollateral do not change any user's credit or debt.
rule creditAndDebtUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector
        && f.selector != sig:updatePosition(Midnight.Market, address).selector
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
rule supplyCollateralEffects(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, market);

    uint256 collateralBefore = collateral(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    supplyCollateral(e, market, collateralIndex, assets, onBehalf);

    assert collateral(id, onBehalf, collateralIndex) == collateralBefore + assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// WITHDRAW COLLATERAL ///

/// withdrawCollateral decreases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule withdrawCollateralCollateralEffects(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, market);

    uint256 collateralBefore = collateral(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);

    assert collateral(id, onBehalf, collateralIndex) == collateralBefore - assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// LIQUIDATE (COLLATERAL) ///

/// liquidate decreases the borrower's collateral at collateralIndex by exactly seizedResult,
/// and only changes position[id][borrower].collateral[collateralIndex].
rule liquidateCollateralEffects(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, market);

    uint256 collateralBefore = collateral(id, borrower, collateralIndex);
    uint256 otherCollateralBefore = collateral(anyId, anyUser, anyIndex);

    uint256 seizedResult;
    seizedResult, _ = liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    assert collateral(id, borrower, collateralIndex) == collateralBefore - seizedResult;
    assert anyUser != borrower || anyId != id || anyIndex != collateralIndex => collateral(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// ALL OTHER FUNCTIONS (COLLATERAL) ///

/// Functions other than supplyCollateral, withdrawCollateral, and liquidate do not change any user's collateral.
rule collateralUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user, uint256 colIdx)
filtered {
    f -> !f.isView
        && f.selector != sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    uint256 collateralBefore = collateral(id, user, colIdx);
    f(e, args);
    assert collateral(id, user, colIdx) == collateralBefore;
}
