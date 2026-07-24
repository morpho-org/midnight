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

    // Getters used by the "empty if not created" invariants assumed below. These invariants are
    // proven in NotCreatedMarket.spec; this conf only verifies the read rule (see the conf's "rule"
    // key), so they are declared here solely to be referenced by requireInvariant.
    function totalUnits(bytes32) external returns (uint128) envfree;
    function withdrawable(bytes32) external returns (uint128) envfree;
    function settlementFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function continuousFee(bytes32) external returns (uint32) envfree;
    function credit(bytes32, address) external returns (uint128) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
}

/// GHOSTS ///

/// Whether a field of a market was read before that market was created.
persistent ghost mapping(bytes32 => bool) marketReadBeforeCreated;

/// HOOKS ///

/// A market is created iff its tickSpacing is non-zero. The hooks below flag the read itself,
/// value-independently: any load of a market field while the market is not yet created flips the
/// ghost, regardless of the value loaded. (Guarding on `val != 0` would make the rule near-vacuous,
/// since an uncreated market's fields are all zero anyway, as proven in NotCreatedMarket.spec.)
/// tickSpacing is deliberately not hooked: the createdness check itself reads it, so hooking it
/// would flag legitimate reads.

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

/// HELPERS ///

function marketIsCreated(bytes32 id) returns (bool) {
    return tickSpacing(id) > 0;
}

function noSettlementFeesAreSet(bytes32 id) returns (bool) {
    uint16[7] fees = settlementFeeCbps(id);
    return fees[0] == 0 && fees[1] == 0 && fees[2] == 0 && fees[3] == 0 && fees[4] == 0 && fees[5] == 0 && fees[6] == 0;
}

definition userHasEmptyCollateralBitmap(bytes32 id, address user) returns bool = currentContract.position[id][user].collateralBitmap == 0;

definition userHasNoRemainingContinuousFee(bytes32 id, address user) returns bool = pendingFee(id, user) == 0;

definition userHasNoLastAccrual(bytes32 id, address user) returns bool = lastAccrual(id, user) == 0;

definition userHasNoCollateral(bytes32 id, address user, uint256 collateralIndex) returns bool = collateralIndex < 128 => currentContract.position[id][user].collateral[collateralIndex] == 0;

/// INVARIANTS ///

// Each market/position field is empty when the market is not created. These are proven in
// NotCreatedMarket.spec (and re-declared here only to be assumed by the rule below); this conf runs
// just the read rule, so they are not re-verified here.
strong invariant marketTotalUnitsIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => totalUnits(id) == 0;

strong invariant marketWithdrawableIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => withdrawable(id) == 0;

strong invariant marketSettlementFeesAreEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => noSettlementFeesAreSet(id);

strong invariant marketContinuousFeeIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => continuousFee(id) == 0;

strong invariant marketContinuousFeeCreditIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => currentContract.marketState[id].continuousFeeCredit == 0;

strong invariant marketLossFactorIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => currentContract.marketState[id].lossFactor == 0;

strong invariant marketCreditIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => credit(id, user) == 0;

strong invariant marketDebtIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => debt(id, user) == 0;

strong invariant marketCollateralBitmapAreEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => userHasEmptyCollateralBitmap(id, user);

strong invariant marketPendingFeeIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => userHasNoRemainingContinuousFee(id, user);

strong invariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => userHasNoLastAccrual(id, user);

strong invariant marketCollateralIsEmptyIfNotCreated(bytes32 id, address user, uint256 collateralIndex)
    !marketIsCreated(id) => userHasNoCollateral(id, user, collateralIndex);

strong invariant positionLastLossFactorIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => currentContract.position[id][user].lastLossFactor == 0;

/// RULES ///

/// Check that no code path reads a field of a market before that market is created. Reads are
/// flagged value-independently by the hooks above. View functions (including the raw storage
/// getters, which legitimately read a field without requiring the market to be created) are excluded
/// by the !f.isView filter. Unreachable prover states (an uncreated market with a non-zero field,
/// which could unlock a control-flow path that reads another field) are excluded via the
/// requireInvariant calls below rather than by filtering zero-valued reads.
rule marketNotReadBeforeCreated(env e, method f, calldataarg args, bytes32 id, address user, uint256 collateralIndex)
filtered {
    f -> !f.isView
} {
    // Exclude states an uncreated market can never actually be in.
    requireInvariant marketTotalUnitsIsEmptyIfNotCreated(id);
    requireInvariant marketWithdrawableIsEmptyIfNotCreated(id);
    requireInvariant marketSettlementFeesAreEmptyIfNotCreated(id);
    requireInvariant marketContinuousFeeIsEmptyIfNotCreated(id);
    requireInvariant marketContinuousFeeCreditIsEmptyIfNotCreated(id);
    requireInvariant marketLossFactorIsEmptyIfNotCreated(id);
    requireInvariant marketCreditIsEmptyIfNotCreated(id, user);
    requireInvariant marketDebtIsEmptyIfNotCreated(id, user);
    requireInvariant marketCollateralBitmapAreEmptyIfNotCreated(id, user);
    requireInvariant marketPendingFeeIsEmptyIfNotCreated(id, user);
    requireInvariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(id, user);
    requireInvariant positionLastLossFactorIsEmptyIfNotCreated(id, user);
    requireInvariant marketCollateralIsEmptyIfNotCreated(id, user, collateralIndex);

    require !marketReadBeforeCreated[id], "initialize the ghost variable";

    f(e, args);

    assert !marketReadBeforeCreated[id], "a market field was read before the market was created";
}
