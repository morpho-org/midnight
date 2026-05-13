// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Midnight.totalUnits(bytes32) external returns (uint256) envfree;
    function Midnight.withdrawable(bytes32) external returns (uint256) envfree;
    function Midnight.tradingFeeCbps(bytes32) external returns (uint16[7]) envfree;
    function Midnight.continuousFee(bytes32) external returns (uint32) envfree;
    function Midnight.toObligation(bytes32) external returns (Midnight.Obligation memory) envfree;
    function Midnight.creditOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.debtOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.pendingFee(bytes32, address) external returns (uint128) envfree;
    function Midnight.lastAccrual(bytes32, address) external returns (uint128) envfree;
    function Midnight.tickSpacing(bytes32) external returns (uint8) envfree;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Summarize CREATE2 opcode used by IdLib.storeInCode.
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

definition WAD() returns uint256 = 10 ^ 18;

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function obligationIsTouched(Midnight.Obligation obligation) returns (bool) {
    return Midnight.tickSpacing(summaryToId(obligation)) > 0;
}

// Show that a touched obligation has at least one collateral.
strong invariant touchedObligationsHaveNonEmptyCollaterals(Midnight.Obligation obligation)
    obligationIsTouched(obligation) => obligation.collateralParams.length > 0;

// Show that a touched obligation has sorted collateralParams.
strong invariant touchedObligationsHaveSortedCollaterals(Midnight.Obligation obligation, uint256 i, uint256 j)
    obligationIsTouched(obligation) => i < j => j < obligation.collateralParams.length => obligation.collateralParams[i].token < obligation.collateralParams[j].token;

// Show that a touched obligation does not have address(0) collateralParams.
strong invariant touchedObligationsHaveNonZeroCollaterals(Midnight.Obligation obligation, uint256 i)
    obligationIsTouched(obligation) => i < obligation.collateralParams.length => obligation.collateralParams[i].token != 0;

// Show that a touched obligation has lltv <= WAD.
strong invariant touchedObligationsHaveLltvLessThanOrEqualToOne(Midnight.Obligation obligation, uint256 i)
    obligationIsTouched(obligation) => i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD();

// Show that a touched obligation cannot be deleted.
rule touchedObligationCannotBeUntouched(env e, method f, calldataarg args, bytes32 id) {
    require Midnight.tickSpacing(id) > 0, "Assume that the obligation is touched";
    f(e, args);
    assert Midnight.tickSpacing(id) > 0;
}

// Show that an obligation is touched after an interaction.

rule obligationIsTouchedAfterTouchObligation(env e, Midnight.Obligation obligation) {
    Midnight.touchObligation(e, obligation);
    assert obligationIsTouched(obligation);
}

rule obligationIsTouchedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    Midnight.take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);
    assert obligationIsTouched(offer.obligation);
}

rule obligationIsTouchedAfterWithdraw(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) {
    Midnight.withdraw(e, obligation, units, onBehalf, receiver);
    assert obligationIsTouched(obligation);
}

rule obligationIsTouchedAfterRepay(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address callback, bytes data) {
    Midnight.repay(e, obligation, units, onBehalf, callback, data);
    assert obligationIsTouched(obligation);
}

rule obligationIsTouchedAfterSupplyCollateral(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) {
    Midnight.supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);
    assert obligationIsTouched(obligation);
}

rule obligationIsTouchedAfterWithdrawCollateral(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    Midnight.withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert obligationIsTouched(obligation);
}

rule obligationIsTouchedAfterLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    Midnight.liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert obligationIsTouched(obligation);
}

// Obligations can only be touched by: touchObligation, take, withdraw, repay, supplyCollateral, withdrawCollateral or liquidate.
rule onlyTouchObligationTouchesObligation(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> f.selector != sig:touchObligation(Midnight.Obligation).selector
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    require Midnight.tickSpacing(id) == 0, "Assume that the obligation is not touched";
    f(e, args);
    assert Midnight.tickSpacing(id) == 0;
}

// Show that each obligation state field is empty if the obligation is not touched.
strong invariant obligationTotalUnitsIsEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => Midnight.totalUnits(id) == 0;

strong invariant obligationWithdrawableIsEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => Midnight.withdrawable(id) == 0;

strong invariant obligationTradingFeesAreEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => noTradingFeesAreSet(id);

strong invariant obligationContinuousFeeIsEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => Midnight.continuousFee(id) == 0;

strong invariant obligationContinuousFeeCreditIsEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => currentContract.obligationState[id].continuousFeeCredit == 0;

strong invariant obligationLossFactorIsEmptyIfNotTouched(bytes32 id)
    Midnight.tickSpacing(id) == 0 => currentContract.obligationState[id].lossFactor == 0;

strong invariant obligationCreditIsEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => Midnight.creditOf(id, user) == 0;

strong invariant obligationDebtIsEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => Midnight.debtOf(id, user) == 0;

strong invariant obligationCollateralBitmapAreEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => userHasEmptyCollateralBitmap(id, user);

strong invariant obligationPendingFeeIsEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => userHasNoRemainingContinuousFee(id, user);

strong invariant obligationLastContinuousFeeAccrualIsEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => userHasNoLastAccrual(id, user);

strong invariant obligationCollateralIsEmptyIfNotTouched(bytes32 id, address user, uint256 collateralIndex)
    Midnight.tickSpacing(id) == 0 => userHasNoCollateral(id, user, collateralIndex);

strong invariant positionLastLossFactorIsEmptyIfNotTouched(bytes32 id, address user)
    Midnight.tickSpacing(id) == 0 => currentContract.position[id][user].lastLossFactor == 0;

function noTradingFeesAreSet(bytes32 id) returns (bool) {
    uint16[7] fees = Midnight.tradingFeeCbps(id);
    return fees[0] == 0 && fees[1] == 0 && fees[2] == 0 && fees[3] == 0 && fees[4] == 0 && fees[5] == 0 && fees[6] == 0;
}

definition userHasEmptyCollateralBitmap(bytes32 id, address user) returns bool = currentContract.position[id][user].collateralBitmap == 0;

definition userHasNoRemainingContinuousFee(bytes32 id, address user) returns bool = Midnight.pendingFee(id, user) == 0;

definition userHasNoLastAccrual(bytes32 id, address user) returns bool = Midnight.lastAccrual(id, user) == 0;

definition userHasNoCollateral(bytes32 id, address user, uint256 collateralIndex) returns bool = collateralIndex < 128 => currentContract.position[id][user].collateral[collateralIndex] == 0;

definition isLltvAllowed(uint256 lltv) returns bool = lltv == 385 * WAD() / 1000 || lltv == 625 * WAD() / 1000 || lltv == 770 * WAD() / 1000 || lltv == 860 * WAD() / 1000 || lltv == 915 * WAD() / 1000 || lltv == 945 * WAD() / 1000 || lltv == 965 * WAD() / 1000 || lltv == 980 * WAD() / 1000 || lltv == WAD();

// Show that a touched obligation only has allowed LLTV tiers.
strong invariant touchedObligationsHaveAllowedLltv(Midnight.Obligation obligation, uint256 i)
    obligationIsTouched(obligation) => i < obligation.collateralParams.length => isLltvAllowed(obligation.collateralParams[i].lltv);
