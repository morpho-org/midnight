// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32) external returns (uint128) envfree;
    function withdrawable(bytes32) external returns (uint128) envfree;
    function settlementFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function continuousFee(bytes32) external returns (uint32) envfree;
    function creditOf(bytes32, address) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint128) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;

    // Over-approximate view functions.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
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
    !marketIsCreated(id) => creditOf(id, user) == 0;

strong invariant marketDebtIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => debtOf(id, user) == 0;

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
