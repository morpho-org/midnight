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
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
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

// take() updates buyer and seller pending fees according to their post-update credit changes:
// 1. the buyer's pendingFee increases by floor(creditIncrease * continuousFee * timeToMaturity / WAD).
// 2. the seller's pendingFee decreases by exactly ceil(postUpdatePendingFee * creditDecrease / postUpdateCredit).
rule pendingFeeAdjustedForBuyerAndSeller(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    bytes32 id;
    uint128 buyerPostUpdateCredit;
    uint128 buyerPostUpdatePendingFee;
    uint128 sellerPostUpdateCredit;
    uint128 sellerPostUpdatePendingFee;

    buyerPostUpdateCredit, buyerPostUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, buyer);
    sellerPostUpdateCredit, sellerPostUpdatePendingFee, _ = updatePositionView(e, offer.obligation, id, seller);

    require sellerPostUpdateCredit > 0 || sellerPostUpdatePendingFee == 0, "See noRemainingContinuousFeeWithoutCredit in Midnight.spec";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id should be derived from obligation";

    uint256 contFee = continuousFee(id);
    uint256 timeToMaturity = e.block.timestamp <= offer.obligation.maturity ? assert_uint256(offer.obligation.maturity - e.block.timestamp) : 0;

    mathint buyerCreditIncrease = to_mathint(creditOf(id, buyer)) - to_mathint(buyerPostUpdateCredit);
    mathint buyerPendingFeeIncrease = to_mathint(pendingFee(id, buyer)) - to_mathint(buyerPostUpdatePendingFee);

    mathint sellerCreditDecrease = to_mathint(sellerPostUpdateCredit) - to_mathint(creditOf(id, seller));
    mathint sellerPendingFeeDecrease = to_mathint(sellerPostUpdatePendingFee) - to_mathint(pendingFee(id, seller));

    assert buyerPendingFeeIncrease == (buyerCreditIncrease * to_mathint(contFee) * to_mathint(timeToMaturity)) / WAD();
    assert sellerPostUpdateCredit == 0 || sellerPendingFeeDecrease == (to_mathint(sellerPostUpdatePendingFee) * sellerCreditDecrease + to_mathint(sellerPostUpdateCredit) - 1) / to_mathint(sellerPostUpdateCredit);
}

// take() increases continuousFeeCredit by exactly the accrued fees of the buyer and seller.
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

// updatePositionView()
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
