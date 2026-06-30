// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tickSpacing(bytes32) external returns (uint8) envfree;
    function isLltvEnabled(uint256) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.maxLif(uint256, uint256) external returns (uint256) envfree;

    // Over-approximate view functions for prover performance.
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    // Deterministic summary of mulDivDown, which is sound because mulDivDown is deterministic.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => ghostMulDivDown(x, y, d);

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Sound because the protocol doesn't use toMarket.
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter, for performance reasons.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

definition WAD() returns uint256 = 10 ^ 18;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// RULES ///

// Show that a created market has at least one collateral.
strong invariant createdMarketsHaveNonEmptyCollaterals(Midnight.Market market)
    marketIsCreated(market) => market.collateralParams.length > 0;

// Show that a created market has sorted collateralParams.
strong invariant createdMarketsHaveSortedCollaterals(Midnight.Market market, uint256 i, uint256 j)
    marketIsCreated(market) => i < j => j < market.collateralParams.length => market.collateralParams[i].token < market.collateralParams[j].token;

// Show that a created market do not have address(0) collateralParams.
strong invariant createdMarketsHaveNonZeroCollaterals(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => market.collateralParams[i].token != 0;

// Show that a created market only has enabled LLTV tiers.
strong invariant createdMarketsHaveEnabledLltv(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => isLltvEnabled(market.collateralParams[i].lltv);

strong invariant createdMarketsHaveEnabledLiquidationCursor(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => currentContract.isLiquidationCursorEnabled[market.collateralParams[i].liquidationCursor];

strong invariant createdMarketsHaveMaxLifAtMostTwoWad(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => Utils.maxLif(market.collateralParams[i].lltv, market.collateralParams[i].liquidationCursor) <= 2 * WAD();

// Show that, except for the special LLTV = 1 case, a created market satisfies lltv * maxLif <= 0.999 * WAD * WAD.
strong invariant createdMarketsRespectMaxLifBound(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => (market.collateralParams[i].lltv == WAD() || market.collateralParams[i].lltv * Utils.maxLif(market.collateralParams[i].lltv, market.collateralParams[i].liquidationCursor) <= 999 * 10 ^ 15 * WAD());

// Show that a created market cannot be deleted.
rule marketCannotBeDeleted(env e, method f, calldataarg args, Midnight.Market market) {
    require marketIsCreated(market), "Assume that the market is created";
    f(e, args);
    assert marketIsCreated(market);
}

// Show that a market is created after an interaction.

rule marketIsCreatedAfterTouchMarket(env e, Midnight.Market market) {
    touchMarket(e, market);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterTake(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    assert marketIsCreated(offer.market);
}

rule marketIsCreatedAfterWithdraw(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    withdraw(e, market, units, onBehalf, receiver);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterRepay(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    repay(e, market, units, onBehalf, callback, data);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterSupplyCollateral(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) {
    supplyCollateral(e, market, collateralIndex, assets, onBehalf);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterWithdrawCollateral(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterLiquidate(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool postMaturityMode) {
    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterClaimContinuousFee(env e, Midnight.Market market, uint256 amount, address receiver) {
    claimContinuousFee(e, market, amount, receiver);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterUpdatePosition(env e, Midnight.Market market, address user) {
    updatePosition(e, market, user);
    assert marketIsCreated(market);
}

// Markets can only be created by: touchMarket, take, withdraw, repay, supplyCollateral, withdrawCollateral, liquidate, claimContinuousFee or updatePosition.
rule onlyTouchMarketCreatesMarket(env e, method f, calldataarg args, Midnight.Market market)
filtered {
    f -> f.selector != sig:touchMarket(Midnight.Market).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
        && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector
        && f.selector != sig:updatePosition(Midnight.Market, address).selector
} {
    require !marketIsCreated(market), "Assume that the market is not created";
    f(e, args);
    assert !marketIsCreated(market);
}
