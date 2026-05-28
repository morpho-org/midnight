// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function claimableSettlementFee(address token) external returns (uint256) envfree;
    function toId(Midnight.Market) external returns (bytes32);
}

rule repayIncreasesWithdrawable(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    bytes32 id = toId(e, market);
    uint256 withdrawableBefore = withdrawable(id);
    repay(e, market, units, onBehalf, callback, data);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore + units;
}

rule liquidateIncreasesWithdrawable(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool postMaturityMode) {
    bytes32 id = toId(e, market);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore + repaidResult;
}

rule withdrawDecreasesWithdrawableExactly(env e, Midnight.Market market, uint256 unitsInput, address onBehalf, address receiver) {
    bytes32 id = toId(e, market);
    uint256 withdrawableBefore = withdrawable(id);
    withdraw(e, market, unitsInput, onBehalf, receiver);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore - unitsInput;
}

rule claimContinuousFeeDecreasesWithdrawableExactly(env e, Midnight.Market market, uint256 amount, address receiver) {
    bytes32 id = toId(e, market);
    uint256 withdrawableBefore = withdrawable(id);
    claimContinuousFee(e, market, amount, receiver);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore - amount;
}

rule withdrawableUnchanged(method f, env e, calldataarg args, bytes32 id)
filtered {
    f -> !f.isView
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector
} {
    uint256 withdrawableBefore = withdrawable(id);
    f(e, args);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore;
}

/// CLAIMABLE SETTLEMENT FEE ///

rule claimDecreasesClaimableSettlementFee(env e, address token, uint256 amount, address receiver) {
    uint256 before = claimableSettlementFee(token);
    claimSettlementFee(e, token, amount, receiver);
    assert claimableSettlementFee(token) == before - amount;
}

rule takeIncreasesClaimableSettlementFee(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, address anyToken) {
    uint256 before = claimableSettlementFee(anyToken);

    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets = take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    // We know that buyerAssets - sellerAssets >= 0, see rule settlementFeeSpreadBounds.
    assert anyToken == offer.market.loanToken => claimableSettlementFee(anyToken) == before + buyerAssets - sellerAssets;
    assert anyToken != offer.market.loanToken => claimableSettlementFee(anyToken) == before;
}

rule claimableSettlementFeeUnchanged(method f, env e, calldataarg args, address token) filtered { f -> !f.isView && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector && f.selector != sig:claimSettlementFee(address, uint256, address).selector } {
    uint256 before = claimableSettlementFee(token);
    f(e, args);
    assert claimableSettlementFee(token) == before;
}
