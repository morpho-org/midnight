// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function Midnight.totalUnits(bytes32) external returns (uint256) envfree;
    function Midnight.withdrawable(bytes32) external returns (uint256) envfree;
    function Midnight.tradingFees(bytes32) external returns (uint16[7]) envfree;
    function Midnight.continuousFee(bytes32) external returns (uint32) envfree;
    function Midnight.obligationCreated(bytes32) external returns (bool) envfree;
    function Midnight.toObligation(bytes32) external returns (Midnight.Obligation memory) envfree;
    function Midnight.creditOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.debtOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.pendingFee(bytes32, address) external returns (uint128) envfree;
    function Midnight.lastAccrual(bytes32, address) external returns (uint128) envfree;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Summarize CREATE2 opcode used by IdLib.storeInCode.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    // Gate functions are view and cannot modify state.
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
}

definition WAD() returns uint256 = 10 ^ 18;

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function obligationIsCreated(Midnight.Obligation obligation) returns (bool) {
    return Midnight.obligationCreated(summaryToId(obligation));
}

// Show that a created obligation has at least one collateral.
strong invariant createdObligationsHaveNonEmptyCollaterals(Midnight.Obligation obligation)
    obligationIsCreated(obligation) => obligation.collateralParams.length > 0;

// Show that a created obligation has sorted collateralParams.
strong invariant createdObligationsHaveSortedCollaterals(Midnight.Obligation obligation, uint256 i, uint256 j)
    obligationIsCreated(obligation) => i < j => j < obligation.collateralParams.length => obligation.collateralParams[i].token < obligation.collateralParams[j].token;

// Show that a created obligation do not have address(0) collateralParams.
strong invariant createdObligationsHaveNonZeroCollaterals(Midnight.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collateralParams.length => obligation.collateralParams[i].token != 0;

// Show that a created obligation has lltv <= WAD.
strong invariant createdObligationsHaveLltvLessThanOrEqualToOne(Midnight.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD();

// Show that a created obligation cannot be deleted.
rule obligationCannotBeDeleted(env e, method f, calldataarg args, bytes32 id) {
    require Midnight.obligationCreated(id), "Assume that the obligation is created";
    f(e, args);
    assert Midnight.obligationCreated(id);
}

// Show that an obligation is created after an interaction.

rule obligationIsCreatedAfterTouchObligation(env e, Midnight.Obligation obligation) {
    Midnight.touchObligation(e, obligation);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    Midnight.take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert obligationIsCreated(offer.obligation);
}

rule obligationIsCreatedAfterWithdraw(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) {
    Midnight.withdraw(e, obligation, units, onBehalf, receiver);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterRepay(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address callback, bytes data) {
    Midnight.repay(e, obligation, units, onBehalf, callback, data);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterSupplyCollateral(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) {
    Midnight.supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterWithdrawCollateral(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    Midnight.withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    Midnight.liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert obligationIsCreated(obligation);
}

// Obligations can only be created by: touchObligation, take, withdraw, repay, supplyCollateral, withdrawCollateral or liquidate.
rule onlyTouchObligationCreatesObligation(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> f.selector != sig:touchObligation(Midnight.Obligation).selector
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address, address, bytes).selector
        && f.selector != sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    require !Midnight.obligationCreated(id), "Assume that the obligation is not created";
    f(e, args);
    assert !Midnight.obligationCreated(id);
}

// Show that each obligation state field is empty if the obligation is not created.
strong invariant obligationTotalUnitsIsEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => Midnight.totalUnits(id) == 0;

strong invariant obligationWithdrawableIsEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => Midnight.withdrawable(id) == 0;

strong invariant obligationTradingFeesAreEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => noTradingFeesAreSet(id);

strong invariant obligationContinuousFeeIsEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => Midnight.continuousFee(id) == 0;

strong invariant obligationContinuousFeeCreditIsEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => currentContract.obligationState[id].continuousFeeCredit == 0;

strong invariant obligationLossIndexIsEmptyIfNotCreated(bytes32 id)
    !Midnight.obligationCreated(id) => currentContract.obligationState[id].lossIndex == 0;

strong invariant obligationCreditIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => Midnight.creditOf(id, user) == 0;

strong invariant obligationDebtIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => Midnight.debtOf(id, user) == 0;

strong invariant obligationActivatedCollateralsAreEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => userHasNoActivatedCollaterals(id, user);

strong invariant obligationPendingFeeIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => userHasNoRemainingContinuousFee(id, user);

strong invariant obligationLastContinuousFeeAccrualIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => userHasNoLastAccrual(id, user);

strong invariant obligationCollateralIsEmptyIfNotCreated(bytes32 id, address user, uint256 collateralIndex)
    !Midnight.obligationCreated(id) => userHasNoCollateral(id, user, collateralIndex);

strong invariant positionLossIndexIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => currentContract.position[id][user].lossIndex == 0;

function noTradingFeesAreSet(bytes32 id) returns (bool) {
    uint16[7] fees = Midnight.tradingFees(id);
    return fees[0] == 0 && fees[1] == 0 && fees[2] == 0 && fees[3] == 0 && fees[4] == 0 && fees[5] == 0 && fees[6] == 0;
}

definition userHasNoActivatedCollaterals(bytes32 id, address user) returns bool = currentContract.position[id][user].activatedCollaterals == 0;

definition userHasNoRemainingContinuousFee(bytes32 id, address user) returns bool = Midnight.pendingFee(id, user) == 0;

definition userHasNoLastAccrual(bytes32 id, address user) returns bool = Midnight.lastAccrual(id, user) == 0;

definition userHasNoCollateral(bytes32 id, address user, uint256 collateralIndex) returns bool = collateralIndex < 128 => currentContract.position[id][user].collateral[collateralIndex] == 0;

definition isLltvAllowed(uint256 lltv) returns bool = lltv == 385 * WAD() / 1000 || lltv == 625 * WAD() / 1000 || lltv == 770 * WAD() / 1000 || lltv == 860 * WAD() / 1000 || lltv == 915 * WAD() / 1000 || lltv == 945 * WAD() / 1000 || lltv == 965 * WAD() / 1000 || lltv == 980 * WAD() / 1000 || lltv == WAD();

// Show that a created obligation only has allowed LLTV tiers.
strong invariant createdObligationsHaveAllowedLltv(Midnight.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collateralParams.length => isLltvAllowed(obligation.collateralParams[i].lltv);
