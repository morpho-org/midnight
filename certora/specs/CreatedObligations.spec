// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using MorphoV2 as MorphoV2;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function MorphoV2.obligationCreated(bytes32) external returns (bool) envfree;
    function Utils.toId(MorphoV2.Obligation, uint256, address) external returns (bytes32) envfree;
    function Utils.naiveId(MorphoV2.Obligation) external returns (bytes32) envfree;
    function Utils.naiveId2(MorphoV2.Obligation) external returns (bytes32) envfree;
    function Utils.naiveId3(MorphoV2.Obligation) external returns (bytes32) envfree;
    function Utils.naiveId4(MorphoV2.Obligation) external returns (bytes32) envfree;

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;

    function IdLib.toId(MorphoV2.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
}

persistent ghost uint256 ghostChainId;

hook CHAINID() uint256 chainId {
    require chainId == ghostChainId;
}

function summaryToId(MorphoV2.Obligation obligation) returns (bytes32) {
    return Utils.toId(obligation, ghostChainId, MorphoV2);
}

// Show that a created obligation has sorted collaterals.
invariant createdObligationsHaveSortedCollaterals(MorphoV2.Obligation obligation, uint256 i, uint256 j)
    MorphoV2.obligationCreated(summaryToId(obligation)) => i < j => j < obligation.collaterals.length => obligation.collaterals[i].token < obligation.collaterals[j].token;

// Show that a created obligation has non-zero collaterals.
invariant createdObligationsHaveNonZeroCollaterals(MorphoV2.Obligation obligation, uint256 i)
    MorphoV2.obligationCreated(summaryToId(obligation)) => i < obligation.collaterals.length => obligation.collaterals[i].token != 0;

// Show that a created obligation cannot be deleted.
rule obligationCannotBeDeleted(env e, method f, calldataarg args, bytes32 id) {
    require MorphoV2.obligationCreated(id), "Assume that the obligation is created";
    f(e, args);
    assert MorphoV2.obligationCreated(id);
}

// Show that an obligation is created after an interaction.

rule obligationIsCreatedAfterTouchObligation(env e, MorphoV2.Obligation obligation) {
    MorphoV2.touchObligation(e, obligation);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule obligationIsCreatedAfterTake(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof) {
    MorphoV2.take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert MorphoV2.obligationCreated(summaryToId(offer.obligation));
}

rule obligationIsCreatedAfterWithdraw(env e, MorphoV2.Obligation obligation, uint256 obligationUnits, uint256 shares, address onBehalf, address receiver) {
    MorphoV2.withdraw(e, obligation, obligationUnits, shares, onBehalf, receiver);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule obligationIsCreatedAfterRepay(env e, MorphoV2.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    MorphoV2.repay(e, obligation, obligationUnits, onBehalf);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule obligationIsCreatedAfterSupplyCollateral(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) {
    MorphoV2.supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule obligationIsCreatedAfterWithdrawCollateral(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    MorphoV2.withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule obligationIsCreatedAfterLiquidate(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    MorphoV2.liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert MorphoV2.obligationCreated(summaryToId(obligation));
}

rule sameIdImpliesSameLoanToken(MorphoV2.Obligation obligation1, MorphoV2.Obligation obligation2) {
    require summaryToId(obligation2) == summaryToId(obligation1), "assume that obligations have the same IDs";

    assert obligation1.loanToken == obligation2.loanToken;
}

rule sameIdNaiveImpliesSameLoanToken(MorphoV2.Obligation obligation1, MorphoV2.Obligation obligation2) {
    require Utils.naiveId(obligation2) == Utils.naiveId(obligation1), "assume that obligations have the same naive IDs";

    assert obligation1.loanToken == obligation2.loanToken;
}

rule sameIdNaive2ImpliesSameLoanToken(MorphoV2.Obligation obligation1, MorphoV2.Obligation obligation2) {
    require Utils.naiveId2(obligation2) == Utils.naiveId2(obligation1), "assume that obligations have the same naive IDs";

    assert obligation1.loanToken == obligation2.loanToken;
}

rule sameIdNaive3ImpliesSameLoanToken(MorphoV2.Obligation obligation1, MorphoV2.Obligation obligation2) {
    require Utils.naiveId3(obligation2) == Utils.naiveId3(obligation1), "assume that obligations have the same naive IDs";

    assert obligation1.loanToken == obligation2.loanToken;
}

rule sameIdNaive4ImpliesSameLoanToken(MorphoV2.Obligation obligation1, MorphoV2.Obligation obligation2) {
    require Utils.naiveId4(obligation2) == Utils.naiveId4(obligation1), "assume that obligations have the same naive IDs";

    assert obligation1.loanToken == obligation2.loanToken;
}
