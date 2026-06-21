// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tickSpacing(bytes32) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

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
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Sound because the protocol doesn't use toMarket.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter, for performance reasons.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

definition WAD() returns uint256 = 10 ^ 18;

definition LLTV_0() returns uint256 = 385000000000000000;

definition LLTV_1() returns uint256 = 625000000000000000;

definition LLTV_2() returns uint256 = 770000000000000000;

definition LLTV_3() returns uint256 = 860000000000000000;

definition LLTV_4() returns uint256 = 915000000000000000;

definition LLTV_5() returns uint256 = 945000000000000000;

definition LLTV_6() returns uint256 = 965000000000000000;

definition LLTV_7() returns uint256 = 980000000000000000;

definition LLTV_8() returns uint256 = WAD();

definition MAX_LIQUIDATION_CURSOR_FOR_LLTV_0() returns uint256 = 813008130081300814;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

definition isLltvAllowed(uint256 lltv) returns bool = lltv == LLTV_0() || lltv == LLTV_1() || lltv == LLTV_2() || lltv == LLTV_3() || lltv == LLTV_4() || lltv == LLTV_5() || lltv == LLTV_6() || lltv == LLTV_7() || lltv == LLTV_8();

definition maxLifAtMostTwoWad(uint256 lltv, uint256 liquidationCursor) returns bool = (lltv == LLTV_0() && liquidationCursor <= MAX_LIQUIDATION_CURSOR_FOR_LLTV_0()) || ((lltv == LLTV_1() || lltv == LLTV_2() || lltv == LLTV_3() || lltv == LLTV_4() || lltv == LLTV_5() || lltv == LLTV_6() || lltv == LLTV_7() || lltv == LLTV_8()) && liquidationCursor <= WAD());

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

// Show that a created market has lltv <= WAD.
strong invariant createdMarketsHaveLltvLessThanOrEqualToOne(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD();

// Show that a created market only has allowed LLTV tiers.
strong invariant createdMarketsHaveAllowedLltv(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => isLltvAllowed(market.collateralParams[i].lltv);

// Show that a created market only has enabled liquidationCursors. Since liquidationCursors are an add-only set, a liquidationCursor enabled
// at creation time stays enabled.
strong invariant createdMarketsHaveEnabledLiquidationCursor(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => currentContract.isLiquidationCursorEnabled[market.collateralParams[i].liquidationCursor];

// Show that enabled liquidationCursors are at most WAD.
strong invariant enabledLiquidationCursorsAreBounded(uint256 liquidationCursor)
    currentContract.isLiquidationCursorEnabled[liquidationCursor] => liquidationCursor <= WAD();

// Show that a created market has maxLif <= 2 WAD for every collateral.
strong invariant createdMarketsHaveMaxLifAtMostTwoWad(Midnight.Market market, uint256 i)
    marketIsCreated(market) => i < market.collateralParams.length => maxLifAtMostTwoWad(market.collateralParams[i].lltv, market.collateralParams[i].liquidationCursor)
    {
        preserved with (env e) {
            requireInvariant createdMarketsHaveEnabledLiquidationCursor(market, i);
            requireInvariant enabledLiquidationCursorsAreBounded(market.collateralParams[i].liquidationCursor);
        }
    }

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

// Markets can only be created by: touchMarket, take, withdraw, repay, supplyCollateral, withdrawCollateral or liquidate.
rule onlyTouchMarketCreatesMarket(env e, method f, calldataarg args, Midnight.Market market)
filtered {
    f -> f.selector != sig:touchMarket(Midnight.Market).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
} {
    require !marketIsCreated(market), "Assume that the market is not created";
    f(e, args);
    assert !marketIsCreated(market);
}
