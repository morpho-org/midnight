// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // The following summaries are sound since they do not read market state.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Market memory) internal returns (bytes32) => NONDET;

    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
}

/// GHOSTS ///

/// Whether a field of a market was read before that market was created.
persistent ghost mapping(bytes32 => bool) marketReadBeforeCreated;

/// HOOKS ///


hook Sload uint128 val marketState[KEY bytes32 id].totalUnits {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].lossFactor {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].withdrawable {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].continuousFeeCredit {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp0 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp1 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp2 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp3 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp4 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp5 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp6 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint32 val marketState[KEY bytes32 id].continuousFee {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].credit {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].pendingFee {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastLossFactor {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastAccrual {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].debt {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateralBitmap {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateral[INDEX uint256 index] {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

/// RULES ///

/// Check that no code path reads a field of a market before that market is created. We exclude only the pure storage getters.
/// updatePositionView and isHealthy are also excluded: they read position fields before any createdness check, but their behavior on an uncreated market is proven by updatePositionViewIsZeroIfMarketNotCreated and marketIsHealthyIfNotCreated in NotCreatedMarket.spec.
rule marketNotReadBeforeCreated(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> f.selector != sig:marketState(bytes32).selector
        && f.selector != sig:position(bytes32, address).selector
        && f.selector != sig:tickSpacing(bytes32).selector
        && f.selector != sig:totalUnits(bytes32).selector
        && f.selector != sig:lossFactor(bytes32).selector
        && f.selector != sig:withdrawable(bytes32).selector
        && f.selector != sig:continuousFee(bytes32).selector
        && f.selector != sig:continuousFeeCredit(bytes32).selector
        && f.selector != sig:settlementFeeCbps(bytes32).selector
        && f.selector != sig:credit(bytes32, address).selector
        && f.selector != sig:debt(bytes32, address).selector
        && f.selector != sig:pendingFee(bytes32, address).selector
        && f.selector != sig:lastAccrual(bytes32, address).selector
        && f.selector != sig:lastLossFactor(bytes32, address).selector
        && f.selector != sig:collateralBitmap(bytes32, address).selector
        && f.selector != sig:collateral(bytes32, address, uint256).selector
        && f.selector != sig:updatePositionView(Midnight.Market, bytes32, address).selector
        && f.selector != sig:isHealthy(Midnight.Market, bytes32, address).selector
} {
    require !marketReadBeforeCreated[id], "initialize the ghost variable";

    f(e, args);

    assert !marketReadBeforeCreated[id], "a market field was read before the market was created";
}
