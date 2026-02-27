// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using MorphoV2 as MorphoV2;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function MorphoV2.totalUnits(bytes20) external returns (uint256) envfree;
    function MorphoV2.totalShares(bytes20) external returns (uint256) envfree;
    function MorphoV2.withdrawable(bytes20) external returns (uint256) envfree;
    function MorphoV2.fees(bytes20) external returns (uint16[7]) envfree;
    function MorphoV2.obligationCreated(bytes20) external returns (bool) envfree;
    function Utils.hashObligation(MorphoV2.Obligation) external returns (bytes32) envfree;

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    // Summary is required because abi.encodePacked doesn't ensure injectivity of the hash function in CVL, for an unknown reason.
    function IdLib.toId(MorphoV2.Obligation memory obligation, uint256, address) internal returns (bytes20) => summaryToId(obligation);
}

// Since the toId function returns a truncated hash, we need to rehash the obligation to ensure injectivity.
persistent ghost mapping(bytes32 => bytes20) rehash {
    axiom forall bytes32 h1. forall bytes32 h2. h1 != h2 => rehash[h1] != rehash[h2];
}

function summaryToId(MorphoV2.Obligation obligation) returns (bytes20) {
    return rehash[Utils.hashObligation(obligation)];
}

function obligationIsCreated(MorphoV2.Obligation obligation) returns (bool) {
    return MorphoV2.obligationCreated(summaryToId(obligation));
}

// Show that a created obligation has sorted collaterals.
invariant createdObligationsHaveSortedCollaterals(MorphoV2.Obligation obligation, uint256 i, uint256 j)
    obligationIsCreated(obligation) => i < j => j < obligation.collaterals.length => obligation.collaterals[i].token < obligation.collaterals[j].token;

// Show that a created obligation does not have address(0) collaterals.
invariant createdObligationsHaveNonZeroCollaterals(MorphoV2.Obligation obligation, uint256 i)
    obligationIsCreated(obligation) => i < obligation.collaterals.length => obligation.collaterals[i].token != 0;

// Show that a created obligation has at least one collateral.
invariant createdObligationsHaveAtLeastOneCollateral(MorphoV2.Obligation obligation)
    obligationIsCreated(obligation) => obligation.collaterals.length > 0;

// Show that a created obligation cannot be deleted.
rule obligationCannotBeDeleted(env e, method f, calldataarg args, bytes20 id) {
    require MorphoV2.obligationCreated(id), "Assume that the obligation is created";
    f(e, args);
    assert MorphoV2.obligationCreated(id);
}

// Show that an obligation is created after an interaction.

rule obligationIsCreatedAfterTouchObligation(env e, MorphoV2.Obligation obligation) {
    MorphoV2.touchObligation(e, obligation);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterTake(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof) {
    MorphoV2.take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert obligationIsCreated(offer.obligation);
}

rule obligationIsCreatedAfterWithdraw(env e, MorphoV2.Obligation obligation, uint256 obligationUnits, uint256 shares, address onBehalf, address receiver) {
    MorphoV2.withdraw(e, obligation, obligationUnits, shares, onBehalf, receiver);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterRepay(env e, MorphoV2.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    MorphoV2.repay(e, obligation, obligationUnits, onBehalf);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterSupplyCollateral(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) {
    MorphoV2.supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterWithdrawCollateral(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    MorphoV2.withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert obligationIsCreated(obligation);
}

rule obligationIsCreatedAfterLiquidate(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    MorphoV2.liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert obligationIsCreated(obligation);
}

// Show that an obligation state is empty if it is not created.
invariant obligationStateIsEmptyIfNotCreated(bytes20 id)
    !MorphoV2.obligationCreated(id) => obligationStateIsEmpty(id);

function obligationStateIsEmpty(bytes20 id) returns (bool) {
    if (MorphoV2.totalUnits(id) != 0) return false;
    if (MorphoV2.totalShares(id) != 0) return false;
    if (MorphoV2.withdrawable(id) != 0) return false;

    uint16[7] fees = MorphoV2.fees(id);
    if (fees[0] != 0) return false;
    if (fees[1] != 0) return false;
    if (fees[2] != 0) return false;
    if (fees[3] != 0) return false;
    if (fees[4] != 0) return false;
    if (fees[5] != 0) return false;
    if (fees[6] != 0) return false;

    return true;
}
