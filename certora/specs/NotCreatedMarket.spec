// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32) external returns (uint128) envfree;
    function withdrawable(bytes32) external returns (uint128) envfree;
    function settlementFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function continuousFee(bytes32) external returns (uint32) envfree;
    function credit(bytes32, address) external returns (uint128) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;

    // Over-approximate view functions.
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
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

/// RULES ///

// Show that each market state field is empty if the market is not created.
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

/// UNCREATED-MARKET BEHAVIOR RULES ///

rule updatePositionViewIsZeroIfMarketNotCreated(env e, Midnight.Market market, bytes32 id, address user) {
    require currentContract.marketState[id].tickSpacing == 0; // the market is not created

    requireInvariant marketCreditIsEmptyIfNotCreated(id, user);
    requireInvariant positionLastLossFactorIsEmptyIfNotCreated(id, user);
    requireInvariant marketLossFactorIsEmptyIfNotCreated(id);
    requireInvariant marketPendingFeeIsEmptyIfNotCreated(id, user);
    requireInvariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(id, user);

    uint128 newCredit;
    uint128 newPendingFee;
    uint128 accruedFee;
    newCredit, newPendingFee, accruedFee = updatePositionView(e, market, id, user);

    assert newCredit == 0;
    assert newPendingFee == 0;
    assert accruedFee == 0;
}

/// isHealthy returns true when the market is not created. The borrower's debt is zero for an
/// uncreated market, so the oracle-querying branch is skipped entirely (no external price() call,
/// hence no havoc) and maxDebt (0) >= debt (0) holds.
rule marketIsHealthyIfNotCreated(env e, Midnight.Market market, bytes32 id, address borrower) {
    require currentContract.marketState[id].tickSpacing == 0; // the market is not created

    requireInvariant marketDebtIsEmptyIfNotCreated(id, borrower);

    assert isHealthy(e, market, id, borrower);
}
