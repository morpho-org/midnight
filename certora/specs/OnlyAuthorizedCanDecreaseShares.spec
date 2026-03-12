// SPDX-License-Identifier: GPL-2.0-or-later

import "Midnight.spec";

methods {
    function feeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function pendingContinuousFee(bytes32 id, address borrower, uint256 maturity) external returns (uint256);
}

use invariant noRemainingContinuousFeeWithoutDebt;

/// An unauthorized caller cannot decrease a user's shares except via take.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant share decreases are not covered.
rule onlyAuthorizedCanDecreaseSharesExceptTake(env e, method f, bytes32 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);
    bool passiveFeeWithdraw = user == Utils.passiveFeeRecipient() && e.msg.sender == feeRecipient() && f.selector == sig:withdraw(Midnight.Obligation, uint256, uint256, address, address).selector;

    require user != e.msg.sender;
    require !isAuthorized(user, e.msg.sender);

    calldataarg args;
    f(e, args);

    assert sharesOf(id, user) >= sharesBefore || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector || passiveFeeWithdraw;
}

/// In take, the caller must be authorized by the taker and only the seller's shares can decrease.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and decrease a different user's shares.
rule takeOnlyAuthorizedSellerSharesDecrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address seller = offer.buy ? taker : offer.maker;
    address buyer = offer.buy ? offer.maker : taker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    bool reverted = lastReverted;
    uint256 sharesAfter = sharesOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => sharesAfter <= sharesBefore;
    assert user != seller => sharesAfter >= sharesBefore;
}

/// A user whose debt is zero can only become a borrower via take.
rule zeroDebtOnlyIncreasesViaTake(env e, method f, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);

    requireInvariant noRemainingContinuousFeeWithoutDebt(id, user);

    calldataarg args;
    f(e, args);

    assert debtBefore > 0 || debtOf(id, user) == 0 || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector;
}

/// In take, the caller must be authorized by the taker, and only the buyer's or seller's debt can change.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and change a different user's debt.
rule takeOnlyAffectsBuyerOrSellerDebt(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    bool reverted = lastReverted;
    uint256 debtAfter = debtOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}

rule withdrawCollateralDebtIncreasesByAccruedFee(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, onBehalf);
    require e.block.timestamp >= require_uint256(lastContinuousFeeAccrual(e, id, onBehalf));
    mathint accruedFeeBefore = pendingContinuousFee(e, id, onBehalf, obligation.maturity);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    require id == lastId;
    assert debtOf(id, onBehalf) == debtBefore + accruedFeeBefore;
}

rule repayDebtMatchesAccrualAndRepayment(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, onBehalf);
    require e.block.timestamp >= require_uint256(lastContinuousFeeAccrual(e, id, onBehalf));
    mathint accruedFeeBefore = pendingContinuousFee(e, id, onBehalf, obligation.maturity);

    repay(e, obligation, obligationUnits, onBehalf);
    require id == lastId;
    assert debtOf(id, onBehalf) + obligationUnits == debtBefore + accruedFeeBefore;
}

rule liquidateDebtIncreaseBoundedByAccruedFee(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, borrower);
    require e.block.timestamp >= require_uint256(lastContinuousFeeAccrual(e, id, borrower));
    mathint accruedFeeBefore = pendingContinuousFee(e, id, borrower, obligation.maturity);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    require id == lastId;
    assert debtOf(id, borrower) <= debtBefore + accruedFeeBefore;
}
