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
}

/// GHOSTS ///

/// Whether a non-empty field of a market was read before that market was created.
persistent ghost mapping(bytes32 => bool) marketReadBeforeCreated;

/// HOOKS ///

/// A market is created iff its tickSpacing is non-zero. Reading a zero value from an uncreated
/// market is harmless (it matches the createdness sentinel itself), so the hooks below only fire
/// when a non-zero field is read while the market is not yet created. tickSpacing is deliberately
/// not hooked: the createdness check itself reads it, so hooking it would flag legitimate reads.

hook Sload uint128 val marketState[KEY bytes32 id].totalUnits {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].lossFactor {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].withdrawable {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].continuousFeeCredit {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp0 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp1 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp2 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp3 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp4 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp5 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp6 {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint32 val marketState[KEY bytes32 id].continuousFee {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].credit {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].pendingFee {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastLossFactor {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastAccrual {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].debt {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateralBitmap {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateral[INDEX uint256 index] {
    if (currentContract.marketState[id].tickSpacing == 0 && val != 0) marketReadBeforeCreated[id] = true;
}

/// RULES ///

/// Check that no code path reads a non-empty field of a market before that market is created.
/// The raw storage getters are filtered out: they legitimately read a field without requiring the
/// market to be created (they return the empty value in that case).
rule marketNotReadBeforeCreated(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> !f.isView
        && f.selector != sig:marketState(bytes32).selector
        && f.selector != sig:position(bytes32, address).selector
        && f.selector != sig:tickSpacing(bytes32).selector
        && f.selector != sig:totalUnits(bytes32).selector
        && f.selector != sig:lossFactor(bytes32).selector
        && f.selector != sig:withdrawable(bytes32).selector
        && f.selector != sig:continuousFee(bytes32).selector
        && f.selector != sig:settlementFeeCbps(bytes32).selector
        && f.selector != sig:credit(bytes32, address).selector
        && f.selector != sig:debt(bytes32, address).selector
        && f.selector != sig:pendingFee(bytes32, address).selector
        && f.selector != sig:lastAccrual(bytes32, address).selector
} {
    require !marketReadBeforeCreated[id], "initialize the ghost variable";

    f(e, args);

    assert !marketReadBeforeCreated[id], "a market field was read before the market was created";
}
