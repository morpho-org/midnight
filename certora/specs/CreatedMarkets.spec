// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Midnight.totalUnits(bytes32) external returns (uint256) envfree;
    function Midnight.withdrawable(bytes32) external returns (uint256) envfree;
    function Midnight.tradingFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function Midnight.continuousFee(bytes32) external returns (uint32) envfree;
    function Midnight.toMarket(bytes32) external returns (Midnight.Market memory) envfree;
    function Midnight.creditOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.debtOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.pendingFee(bytes32, address) external returns (uint128) envfree;
    function Midnight.lastAccrual(bytes32, address) external returns (uint128) envfree;
    function Midnight.tickSpacing(bytes32) external returns (uint8) envfree;
    function Midnight.isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

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
    return Midnight.tickSpacing(id) > 0;
}

// Show that a created market has at least one collateral.
strong invariant createdMarketsHaveNonEmptyCollaterals(Midnight.Market market)
    marketIsCreated(market) => market.collateralParams.length > 0;

// Show that a created market has sorted collateralParams.
strong invariant createdMarketsHaveSortedCollaterals(Midnight.Market market, uint256 i, uint256 j)
    marketIsCreated(market) => i < j => j < market.collateralParams.length => market.collateralParams[i].token < market.collateralParams[j].token;

// Show that a created market do not have address(0) collateralParams.
strong invariant createdMarketsHaveNonZeroCollaterals(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => market.collateralParams[i].token != 0;

// Show that a created market has lltv <= WAD.
strong invariant createdMarketsHaveLltvLessThanOrEqualToOne(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD();

// Show that a created market cannot be deleted.
rule marketCannotBeDeleted(env e, method f, calldataarg args, bytes32 id) {
    require marketCreated(id), "Assume that the market is created";
    f(e, args);
    assert marketCreated(id);
}

// Show that a market is created after an interaction.

rule marketIsCreatedAfterTouchMarket(env e, Midnight.Market market) {
    Midnight.touchMarket(e, market);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    Midnight.take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);
    assert marketIsCreated(offer.market);
}

rule marketIsCreatedAfterWithdraw(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    Midnight.withdraw(e, market, units, onBehalf, receiver);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterRepay(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    Midnight.repay(e, market, units, onBehalf, callback, data);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterSupplyCollateral(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) {
    Midnight.supplyCollateral(e, market, collateralIndex, assets, onBehalf);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterWithdrawCollateral(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    Midnight.withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);
    assert marketIsCreated(market);
}

rule marketIsCreatedAfterLiquidate(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    Midnight.liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert marketIsCreated(market);
}

definition isLltvAllowed(uint256 lltv) returns bool = lltv == 385 * WAD() / 1000 || lltv == 625 * WAD() / 1000 || lltv == 770 * WAD() / 1000 || lltv == 860 * WAD() / 1000 || lltv == 915 * WAD() / 1000 || lltv == 945 * WAD() / 1000 || lltv == 965 * WAD() / 1000 || lltv == 980 * WAD() / 1000 || lltv == WAD();

// Show that a created market only has allowed LLTV tiers.
strong invariant createdMarketsHaveAllowedLltv(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => isLltvAllowed(market.collateralParams[i].lltv);
