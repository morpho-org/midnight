// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;

    // Summarize internals irrelevant to continuous fee tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function tradingFee(bytes32 id, uint256 timeToMaturity) internal returns (uint256) => NONDET;

    // summaries over-approximating the behavior of transient storage.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;
}

/// HELPERS ///

// IdLib summary: remember the last id returned by toId.

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    // non-deterministic id
    bytes32 id;
    lastId = id;
    return id;
}

definition WAD() returns uint256 = 10 ^ 18;

// The buyer's pendingFee increases by floor(creditIncrease * continuousFee * timeToMaturity / WAD).
rule continuousFeeNotOverchargedForBuyer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    address buyer = offer.buy ? offer.maker : taker;

    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, buyer);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 contFee = continuousFee(id);
    uint256 timeToMaturity = e.block.timestamp <= offer.obligation.maturity ? assert_uint256(offer.obligation.maturity - e.block.timestamp) : 0;

    mathint creditDelta = to_mathint(creditOf(id, buyer)) - to_mathint(postUpdateCredit);
    mathint pendingFeeDelta = to_mathint(pendingFee(id, buyer)) - to_mathint(postUpdatePendingFee);

    assert pendingFeeDelta == (creditDelta * to_mathint(contFee) * to_mathint(timeToMaturity)) / WAD();
}

// When a seller's credit decreases via a take, their pendingFee decreases by exactly ceil(PendingFee * creditDelta / postUpdateCredit).
rule pendingFeeDecreasesProportionallyForSeller(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, seller);

    require postUpdateCredit > 0 || postUpdatePendingFee == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 creditAfter = creditOf(id, seller);
    uint256 pendingFeeAfter = pendingFee(id, seller);

    require creditAfter > 0 || pendingFeeAfter == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    mathint creditDelta = to_mathint(postUpdateCredit) - to_mathint(creditAfter);
    mathint pendingFeeDelta = to_mathint(postUpdatePendingFee) - to_mathint(pendingFeeAfter);

    // When postUpdateCredit == 0: noRemainingContinuousFeeWithoutCredit gives postUpdatePendingFee == 0; credit is non-increasing for a seller, therefore creditAfter == 0;
    // noRemainingContinuousFeeWithoutCredit gives pendingFeeAfter == 0; hence pendingFeeDelta == 0.
    assert postUpdateCredit == 0 ? pendingFeeDelta == 0 : pendingFeeDelta == (to_mathint(postUpdatePendingFee) * creditDelta + to_mathint(postUpdateCredit) - 1) / to_mathint(postUpdateCredit);
}

// take() increases continuousFeeCredit by exactly the sum of the accrued fees of the buyer and seller.
rule continuousFeeCreditIncreasesByAccruedFees(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 buyerAccruedFee;
    uint128 sellerAccruedFee;

    _, _, buyerAccruedFee = updatePositionView(e, offer.obligation, id, buyer);
    _, _, sellerAccruedFee = updatePositionView(e, offer.obligation, id, seller);

    uint256 continuousFeeCreditBefore = continuousFeeCredit(id);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id should be derived from obligation";

    assert continuousFeeCredit(id) == continuousFeeCreditBefore + buyerAccruedFee + sellerAccruedFee;
}

rule takeDoesNotAffectThirdParties(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require user != buyer && user != seller, "user is different from buyer and seller";

    bytes32 id;
    uint256 postUpdateCreditBefore;
    uint256 postUpdatePendingFeeBefore;
    uint256 userAccruedFeeBefore;
    postUpdateCreditBefore, postUpdatePendingFeeBefore, userAccruedFeeBefore = updatePositionView(e, offer.obligation, id, user);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 postUpdateCreditAfter;
    uint256 postUpdatePendingFeeAfter;
    uint256 userAccruedFeeAfter;
    postUpdateCreditAfter, postUpdatePendingFeeAfter, userAccruedFeeAfter = updatePositionView(e, offer.obligation, id, user);

    assert postUpdateCreditBefore == postUpdateCreditAfter, "take should not change credit of third party";
    assert postUpdatePendingFeeBefore == postUpdatePendingFeeAfter, "take should not change pending fee of third party";
    assert userAccruedFeeBefore == userAccruedFeeAfter, "take should not change accrued fee of third party";
}
