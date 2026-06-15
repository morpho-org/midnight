// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function lossFactor(bytes32 id) external returns (uint128) envfree;
    function toId(Midnight.Market) external returns (bytes32) envfree;
}

/// The up-to-date face value of a lender's position: credit - pendingFee after slashing and fee accrual.
/// The continuous fee cancels out (it is subtracted from both credit and pendingFee), so this only
/// reflects withdrawals, take transfers, and bad-debt slashing via the market loss factor.
function netCredit(env e, Midnight.Market market, address user) returns mathint {
    bytes32 id = toId(market);
    uint128 credit;
    uint128 pending;
    uint128 accruedFee;
    credit, pending, accruedFee = updatePositionView(e, market, id, user);
    return credit - pending;
}

/// The up-to-date face value of a lender's position (credit - pendingFee) can only decrease by
/// withdrawing, taking, or liquidating. Every other function leaves it unchanged or increases it.
rule creditNondecreasing(env e, method f, calldataarg args, Midnight.Market market, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
} {
    mathint creditBefore = netCredit(e, market, user);

    f(e, args);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter >= creditBefore;
}

/// Withdrawing on behalf of another account does not decrease an unrelated user's net credit.
rule withdrawDoesNotDecreaseOtherCredit(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver, address user) {
    require user != onBehalf;

    mathint creditBefore = netCredit(e, market, user);

    withdraw(e, market, units, onBehalf, receiver);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter >= creditBefore;
}

/// Taking does not decrease the net credit of a user that is neither the taker nor the offer's maker.
rule takeDoesNotDecreaseUninvolvedCredit(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    require user != taker && user != offer.maker;

    mathint creditBefore = netCredit(e, offer.market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    mathint creditAfter = netCredit(e, offer.market, user);

    assert creditAfter >= creditBefore;
}

/// Liquidating does not decrease any user's net credit as long as no bad debt is realized,
/// i.e. the market loss factor is unchanged by the liquidation.
rule liquidateWithoutBadDebtDoesNotDecreaseCredit(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, address user) {
    bytes32 id = toId(market);
    uint128 lossFactorBefore = lossFactor(id);

    mathint creditBefore = netCredit(e, market, user);

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    // Restrict to executions in which no bad debt was realized.
    require lossFactor(id) == lossFactorBefore;

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter >= creditBefore;
}
