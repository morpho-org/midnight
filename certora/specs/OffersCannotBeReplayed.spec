// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function consumed(address user, bytes32 group) external returns (uint256) envfree;

    function _.price() external => PER_CALLEE_CONSTANT;

    function _.onBuy(MorphoV2.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(MorphoV2.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}


// Offers cannot be replayed
// Consume is monotonically non-decreasing across all functions.

/// consumed[user][group] is monotonically non-decreasing across all functions.
rule consumedNeverDecreases(env e, method f, address user, bytes32 group)
filtered { f -> !f.isView } {
    uint256 consumedBefore = consumed(user, group);

    calldataarg args;
    f(e, args);

    assert consumed(user, group) >= consumedBefore;
}

/// A fully-consumed offer always reverts when the take input is non-zero in the offer's consumption dimension.
rule fullyConsumedOfferRevertsOnNonTrivialTake(
    env e, uint256 buyerAssets, uint256 sellerAssets,
    uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root,
    bytes32[] proof
) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    // weird require due to rounding down to 0 in take
    require (offer.assets > 0 && consumedBefore >= offer.assets && (offer.buy ? buyerAssets > 0 : sellerAssets > 0))
         || (offer.obligationUnits > 0 && consumedBefore >= offer.obligationUnits && obligationUnits > 0)
         || (offer.obligationShares > 0 && consumedBefore >= offer.obligationShares  && obligationShares > 0);

    take@withrevert(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert lastReverted;
}
