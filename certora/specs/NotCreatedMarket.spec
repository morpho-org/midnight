// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32) external returns (uint256) envfree;
    function withdrawable(bytes32) external returns (uint256) envfree;
    function tradingFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function continuousFee(bytes32) external returns (uint32) envfree;
    function toMarket(bytes32) external returns (Midnight.Market memory) envfree;
    function creditOf(bytes32, address) external returns (uint256) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Summarize CREATE2 opcode used by IdLib.storeInCode.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

definition WAD() returns uint256 = 10 ^ 18;

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return marketCreated(summaryToId(market));
}

function marketCreated(bytes32 id) returns (bool) {
    return tickSpacing(id) > 0;
}

// Show that a market is created after an interaction.

rule marketIsCreatedAfterTouchMarket(env e, Midnight.Market market) {
    touchMarket(e, market);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);
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

rule marketIsCreatedAfterLiquidate(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert marketIsCreated(market);
}

// Markets can only be created by: touchMarket, take, withdraw, repay, supplyCollateral, withdrawCollateral or liquidate.
rule onlyTouchMarketCreatesMarket(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> f.selector != sig:touchMarket(Midnight.Market).selector
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    require !marketCreated(id), "Assume that the market is not created";
    f(e, args);
    assert !marketCreated(id);
}

// Show that each market state field is empty if the market is not created.
strong invariant marketTotalUnitsIsEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => totalUnits(id) == 0;

strong invariant marketWithdrawableIsEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => withdrawable(id) == 0;

strong invariant marketTradingFeesAreEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => noTradingFeesAreSet(id);

strong invariant marketContinuousFeeIsEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => continuousFee(id) == 0;

strong invariant marketContinuousFeeCreditIsEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => currentContract.marketState[id].continuousFeeCredit == 0;

strong invariant marketLossFactorIsEmptyIfNotCreated(bytes32 id)
    !marketCreated(id) => currentContract.marketState[id].lossFactor == 0;

strong invariant marketCreditIsEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => creditOf(id, user) == 0;

strong invariant marketDebtIsEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => debtOf(id, user) == 0;

strong invariant marketCollateralBitmapAreEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => userHasEmptyCollateralBitmap(id, user);

strong invariant marketPendingFeeIsEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => userHasNoRemainingContinuousFee(id, user);

strong invariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => userHasNoLastAccrual(id, user);

strong invariant marketCollateralIsEmptyIfNotCreated(bytes32 id, address user, uint256 collateralIndex)
    !marketCreated(id) => userHasNoCollateral(id, user, collateralIndex);

strong invariant positionLastLossFactorIsEmptyIfNotCreated(bytes32 id, address user)
    !marketCreated(id) => currentContract.position[id][user].lastLossFactor == 0;

function noTradingFeesAreSet(bytes32 id) returns (bool) {
    uint16[7] fees = tradingFeeCbps(id);
    return fees[0] == 0 && fees[1] == 0 && fees[2] == 0 && fees[3] == 0 && fees[4] == 0 && fees[5] == 0 && fees[6] == 0;
}

definition userHasEmptyCollateralBitmap(bytes32 id, address user) returns bool = currentContract.position[id][user].collateralBitmap == 0;

definition userHasNoRemainingContinuousFee(bytes32 id, address user) returns bool = pendingFee(id, user) == 0;

definition userHasNoLastAccrual(bytes32 id, address user) returns bool = lastAccrual(id, user) == 0;

definition userHasNoCollateral(bytes32 id, address user, uint256 collateralIndex) returns bool = collateralIndex < 128 => currentContract.position[id][user].collateral[collateralIndex] == 0;
