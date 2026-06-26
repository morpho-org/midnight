// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Record every call to touchMarket and the market it is called with.
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => recordTouchMarket(market);

    // Over-approximate the heavy functions for prover performance.
    // This is safe here: the worst they could do is fail to record a touchMarket call, which would make a rule fail rather than pass unsoundly.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

persistent ghost bool touchMarketCalled;

persistent ghost bytes32 touchedMarketId;

function recordTouchMarket(Midnight.Market market) returns bytes32 {
    touchMarketCalled = true;
    touchedMarketId = Utils.hashMarket(market);
    return Utils.hashMarket(market);
}

/// RULES ///

// Each rule shows that a successful interaction calls touchMarket with its own market, which in turn implies that a reverting touchMarket forces the interaction to revert.

rule claimContinuousFeeCallsTouchMarket(env e, Midnight.Market market, uint256 amount, address receiver) {
    require !touchMarketCalled, "reset call tracking";

    claimContinuousFee(e, market, amount, receiver);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule takeCallsTouchMarket(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    require !touchMarketCalled, "reset call tracking";

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(offer.market);
}

rule withdrawCallsTouchMarket(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    require !touchMarketCalled, "reset call tracking";

    withdraw(e, market, units, onBehalf, receiver);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule repayCallsTouchMarket(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    require !touchMarketCalled, "reset call tracking";

    repay(e, market, units, onBehalf, callback, data);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule supplyCollateralCallsTouchMarket(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) {
    require !touchMarketCalled, "reset call tracking";

    supplyCollateral(e, market, collateralIndex, assets, onBehalf);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule withdrawCollateralCallsTouchMarket(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    require !touchMarketCalled, "reset call tracking";

    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule liquidateCallsTouchMarket(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool postMaturityMode) {
    require !touchMarketCalled, "reset call tracking";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}

rule updatePositionCallsTouchMarket(env e, Midnight.Market market, address user) {
    require !touchMarketCalled, "reset call tracking";

    updatePosition(e, market, user);

    assert touchMarketCalled;
    assert touchedMarketId == Utils.hashMarket(market);
}
