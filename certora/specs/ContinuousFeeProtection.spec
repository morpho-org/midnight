// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lossIndex(bytes32 id) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;

    function _.price() external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function tradingFee(bytes32 id, uint256 timeToMaturity) internal returns (uint256) => NONDET;

    // the properties are about pendingFee/ credit accounting, and not liquidation interactions.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
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

// In a buy-offer take, the buyer's pendingFee increases by at most floor(creditIncrease * continuousFee * timeToMaturity / WAD).
rule continuousFeeNotOverchargedInBuyOffer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 contFee = continuousFee(id);
    uint256 timeToMaturity = e.block.timestamp <= offer.obligation.maturity ? assert_uint256(offer.obligation.maturity - e.block.timestamp) : 0;

    mathint creditDelta = to_mathint(creditOf(id, offer.maker)) - to_mathint(postUpdateCredit);
    mathint pendingFeeDelta = to_mathint(pendingFee(id, offer.maker)) - to_mathint(postUpdatePendingFee);

    require offer.buy, "scope to buy offers";

    assert pendingFeeDelta <= (creditDelta * to_mathint(contFee) * to_mathint(timeToMaturity)) / WAD();
}

// When a seller's credit decreases via a take, their pendingFee decreases by exactly ceil(postUpdatePendingFee * creditDecrease / postUpdateCredit).
rule pendingFeeDecreasesProportionallyInSellOffer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;

    postUpdateCredit, postUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, offer.maker);

    require postUpdateCredit > 0 || postUpdatePendingFee == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 creditAfter = creditOf(id, offer.maker);
    uint256 pendingFeeAfter = pendingFee(id, offer.maker);

    mathint creditDelta = to_mathint(postUpdateCredit) - to_mathint(creditAfter);
    mathint pendingFeeDelta = to_mathint(postUpdatePendingFee) - to_mathint(pendingFeeAfter);

    require offer.buy == false, "scope to sell offers";

    assert postUpdateCredit == 0 || pendingFeeDelta == (to_mathint(postUpdatePendingFee) * creditDelta + to_mathint(postUpdateCredit) - 1) / to_mathint(postUpdateCredit);
}

// take() increases continuousFeeCredit by exactly the accrued fees of the buyer and seller.
rule continuousFeeCreditIncreasesByAccruedFees(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 buyerAccruedFee;
    uint128 sellerAccruedFee;

    _, _, buyerAccruedFee = updatePositionView(e, offer.obligation, id, buyer);
    _, _, sellerAccruedFee = updatePositionView(e, offer.obligation, id, seller);

    uint256 continuousFeeCreditBefore = continuousFeeCredit(id);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId, "id should be derived from obligation";

    assert continuousFeeCredit(id) == continuousFeeCreditBefore + buyerAccruedFee + sellerAccruedFee;
}

// take() must not modify credit or pendingFee of any address other than the buyer and seller.
rule takeDoesNotAffectThirdParties(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require user != buyer && user != seller, "user is different from buyer and seller";

    bytes32 id;
    uint256 creditBefore = creditOf(id, user);
    uint256 pendingFeeBefore = pendingFee(id, user);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId, "id should be derived from obligation";

    assert creditOf(id, user) == creditBefore;
    assert pendingFee(id, user) == pendingFeeBefore;
}
