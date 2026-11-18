// SPDX-License-Identifier: MIT

import "NetCredit.spec";

methods {
    // The callback may reenter Midnight once by withdrawing its own credit,
    // as MidnightAdapter does on self-funded buys.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address buyer, bytes) external with(env e) => onBuySummary(e, calledContract, buyer) expect(bytes32);
}

persistent ghost bool onBuyCalled;

persistent ghost address onBuyCallee;

persistent ghost address onBuyBuyer;

function onBuySummary(env e, address callee, address buyer) returns (bytes32) {
    onBuyCalled = true;
    onBuyCallee = callee;
    onBuyBuyer = buyer;

    bool reenterWithdraw;
    if (reenterWithdraw) {
        env reentrantEnv;
        require reentrantEnv.msg.sender == callee;
        require reentrantEnv.block.timestamp == e.block.timestamp;
        Midnight.Market market;
        uint256 units;
        withdraw(reentrantEnv, market, units, callee, callee);
    }

    bytes32 result;
    return result;
}

// NetCredit.spec proves every entry point other than take leaves net credit unchanged or cannot increase it.
// This rule covers the remaining increase path: take requires onBuy for the buyer when its callback is configured.
rule netCreditIncreaseCallsOnBuy(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address buyerCallback = offer.buy ? offer.callback : takerCallback;
    require buyerCallback != 0, "the buyer-side callback is set, so take calls onBuy";
    require !onBuyCalled, "onBuy has not been called yet in this transaction";

    mathint netCreditBefore = netCredit(e, offer.market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    require continuousFee(summaryToId(offer.market)) <= MAX_CONTINUOUS_FEE(), "See continuousFeeBounded in Midnight.sol";
    requireInvariant maturityBoundedById(summaryToId(offer.market));

    mathint netCreditAfter = netCredit(e, offer.market, user);

    assert netCreditAfter > netCreditBefore => user == buyer && onBuyCalled && onBuyCallee == buyerCallback && onBuyBuyer == user;
}
