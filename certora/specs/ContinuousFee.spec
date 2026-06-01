// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => CVL_toId(market);

    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint128) envfree;

    // Summarize internals irrelevant to continuous fee tracking.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;

    // summaries over-approximating the behavior of transient storage.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;

    // Assume no reentrancy: callbacks and transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own body on the continuous fee, not the effect of the full transaction including callbacks.
}

/// HELPERS ///

// IdLib summary: remember the last id returned by toId.

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Market market) returns bytes32 {
    // non-deterministic id
    bytes32 id;
    lastId = id;
    return id;
}

definition WAD() returns uint256 = 10 ^ 18;

// The buyer's pendingFee increases by floor(creditIncrease * continuousFee * timeToMaturity / WAD).
rule continuousFeeNotOverchargedForBuyer(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    address buyer = offer.buy ? offer.maker : taker;

    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.market, id, buyer);

    require pendingFee(id, buyer) <= creditOf(id, buyer), "See pendingContinuousFeeBoundedByCredit in Midnight.spec";

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    uint256 contFee = continuousFee(id);
    uint256 timeToMaturity = e.block.timestamp <= offer.market.maturity ? assert_uint256(offer.market.maturity - e.block.timestamp) : 0;

    mathint creditDelta = creditOf(id, buyer) - postUpdateCredit;

    assert pendingFee(id, buyer) == postUpdatePendingFee + (creditDelta * contFee * timeToMaturity) / WAD();
}

// When a seller's credit decreases via a take, their pendingFee decreases by ceil(PendingFee * creditDelta / postUpdateCredit).
rule pendingFeeDecreasesProportionallyForSeller(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.market, id, seller);

    require postUpdateCredit > 0 || postUpdatePendingFee == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    uint256 creditAfter = creditOf(id, seller);
    uint256 pendingFeeAfter = pendingFee(id, seller);

    require creditAfter > 0 || pendingFeeAfter == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    mathint creditDelta = postUpdateCredit - creditAfter;

    // When postUpdateCredit == 0: noRemainingContinuousFeeWithoutCredit gives postUpdatePendingFee == 0; credit is non-increasing for a seller, therefore creditAfter == 0;
    // noRemainingContinuousFeeWithoutCredit gives pendingFeeAfter == 0; hence pendingFeeDelta == 0.
    assert postUpdateCredit == 0 ? postUpdatePendingFee == pendingFeeAfter : postUpdatePendingFee == pendingFeeAfter + (postUpdatePendingFee * creditDelta + postUpdateCredit - 1) / postUpdateCredit;
}

// When credit decreases via withdraw, pendingFee decreases by ceil(pendingFee * units / postUpdateCredit).
rule pendingFeeDecreasesProportionallyOnWithdraw(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, market, id, onBehalf);

    withdraw(e, market, units, onBehalf, receiver);

    require id == lastId, "id should be derived from market";

    // When postUpdateCredit == 0, pendingFee(id, onBehalf) is unchanged on withdraw.
    assert postUpdateCredit == 0 ? pendingFee(id, onBehalf) == postUpdatePendingFee : pendingFee(id, onBehalf) == postUpdatePendingFee - (postUpdatePendingFee * units + postUpdateCredit - 1) / postUpdateCredit;
}

// take() increases continuousFeeCredit by exactly the sum of the accrued fees of the buyer and seller.
rule continuousFeeCreditIncreasesByAccruedFees(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 buyerAccruedFee;
    uint128 sellerAccruedFee;

    _, _, buyerAccruedFee = updatePositionView(e, offer.market, id, buyer);
    _, _, sellerAccruedFee = updatePositionView(e, offer.market, id, seller);

    uint256 continuousFeeCreditBefore = continuousFeeCredit(id);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    assert continuousFeeCredit(id) == continuousFeeCreditBefore + buyerAccruedFee + sellerAccruedFee;
}

// take should not change the return values of updatePositionView (i.e., post-update credit, pending fee, and accrued fee) of a third party.
rule takeDoesNotAffectThirdParties(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require user != buyer && user != seller, "user is different from buyer and seller";

    bytes32 id;
    uint256 postUpdateCreditBefore;
    uint256 postUpdatePendingFeeBefore;
    uint256 userAccruedFeeBefore;
    postUpdateCreditBefore, postUpdatePendingFeeBefore, userAccruedFeeBefore = updatePositionView(e, offer.market, id, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require id == lastId, "id should be derived from market";

    uint256 postUpdateCreditAfter;
    uint256 postUpdatePendingFeeAfter;
    uint256 userAccruedFeeAfter;
    postUpdateCreditAfter, postUpdatePendingFeeAfter, userAccruedFeeAfter = updatePositionView(e, offer.market, id, user);

    assert postUpdateCreditBefore == postUpdateCreditAfter;
    assert postUpdatePendingFeeBefore == postUpdatePendingFeeAfter;
    assert userAccruedFeeBefore == userAccruedFeeAfter;
}
