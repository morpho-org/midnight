// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes20);

    function _.price() external => PER_CALLEE_CONSTANT;

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
    env e, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    Midnight.Offer offer, Midnight.Signature signature, bytes32 root,
    bytes32[] proof
) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    bytes20 id = toId(e, offer.obligation);
    uint256 _totalUnits = totalUnits(id);
    uint256 _totalShares = totalShares(id);

    require (offer.obligationUnits > 0 && consumedBefore >= offer.obligationUnits && obligationShares > 0)
         || (offer.obligationShares > 0 && consumedBefore >= offer.obligationShares && obligationShares > 0);

    // When consumption is units-based, prevent rounding down to 0
    require offer.obligationUnits > 0 => to_mathint(obligationShares) * (to_mathint(_totalUnits) + 1) >= to_mathint(_totalShares) + 1;

    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert lastReverted;
}
