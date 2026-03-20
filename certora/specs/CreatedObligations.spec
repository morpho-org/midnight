// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function Midnight.totalUnits(bytes32) external returns (uint256) envfree;
    function Midnight.withdrawable(bytes32) external returns (uint256) envfree;
    function Midnight.fees(bytes32) external returns (uint16[7]) envfree;
    function Midnight.obligationCreated(bytes32) external returns (bool) envfree;
    function Midnight.creditOf(bytes32, address) external returns (uint256) envfree;
    function Midnight.debtOf(bytes32, address) external returns (uint256) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
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
    obligationIsCreated(obligation) => obligation.collaterals.length > 0;

// Show that a created obligation has sorted collaterals.
strong invariant createdObligationsHaveSortedCollaterals(Midnight.Obligation obligation, uint256 i, uint256 j)
    obligationIsCreated(obligation) => i < j => j < obligation.collaterals.length => obligation.collaterals[i].token < obligation.collaterals[j].token;

// Show that a created obligation do not have address(0) collaterals.
strong invariant createdObligationsHaveNonZeroCollaterals(Midnight.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collaterals.length => obligation.collaterals[i].token != 0;

// Show that a created obligation has lltv <= WAD.
strong invariant createdObligationsHaveLltvLessThanOrEqualToOne(Midnight.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collaterals.length => obligation.collaterals[i].lltv <= WAD();

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

rule obligationIsCreatedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    Midnight.take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert obligationIsCreated(offer.obligation);
}

rule obligationIsCreatedAfterWithdraw(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) {
    Midnight.withdraw(e, obligation, units, onBehalf, receiver);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterRepay(env e, Midnight.Obligation obligation, uint256 units, address onBehalf) {
    Midnight.repay(e, obligation, units, onBehalf);
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

rule obligationIsCreatedAfterLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    Midnight.liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert obligationIsCreated(obligation);
}

// Show that an obligation state is empty if it is not created.
strong invariant obligationStateIsEmptyIfNotCreated(bytes32 id, address user)
    !Midnight.obligationCreated(id) => obligationStateIsEmpty(id, user);

definition obligationStateIsEmpty(bytes32 id, address user) returns bool = Midnight.totalUnits(id) == 0 && Midnight.withdrawable(id) == 0 && noFeesAreSet(id) && Midnight.creditOf(id, user) == 0 && Midnight.debtOf(id, user) == 0 && userHasNoActivatedCollaterals(id, user) && userHasNoCollateral(id, user) && currentContract.obligationState[id].lossIndex == 0 && currentContract.position[id][user].lossIndex == 0;

function noFeesAreSet(bytes32 id) returns (bool) {
    uint16[7] fees = Midnight.fees(id);
    return fees[0] == 0 && fees[1] == 0 && fees[2] == 0 && fees[3] == 0 && fees[4] == 0 && fees[5] == 0 && fees[6] == 0;
}

definition userHasNoActivatedCollaterals(bytes32 id, address user) returns bool = currentContract.position[id][user].activatedCollaterals == 0;

definition userHasNoCollateral(bytes32 id, address user) returns bool = forall uint256 collateralIndex. collateralIndex < 128 => currentContract.position[id][user].collateral[collateralIndex] == 0;
