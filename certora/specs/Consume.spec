// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;

    // Summaries for complex internals irrelevant to consumed-mapping properties.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
}

///  Only `setConsumed` and `take` can modify the `consumed` mapping.
rule onlySetConsumedAndTakeChangeConsumed(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> f.selector != sig:setConsumed(bytes32, uint256, address).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    uint256 consumedBefore = consumed(user, group);

    f(e, args);

    assert consumed(user, group) == consumedBefore;
}

/// Calling `setConsumed` only affects onBehalf's consumed value for the given group.
/// No other (user, group) pair is modified.
rule setConsumedOnlyAffectsOnBehalf(env e, bytes32 group, uint256 amount, address onBehalf, address otherUser, bytes32 otherGroup) {
    uint256 otherConsumedBefore = consumed(otherUser, otherGroup);

    setConsumed(e, group, amount, onBehalf);

    // Any pair that is not (onBehalf, group) remains unchanged.
    assert (otherUser != onBehalf || otherGroup != group) => consumed(otherUser, otherGroup) == otherConsumedBefore;
}

/// Calling `take` only affects the maker's consumed value for the offer's group.
/// No other (user, group) pair is modified.
rule takeOnlyAffectsMakerConsumed(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof, address user, bytes32 group) {
    uint256 consumedBefore = consumed(user, group);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    // Any pair that is not exactly (offer.maker, offer.group) must be unchanged.
    assert (user != offer.maker || group != offer.group) => consumed(user, group) == consumedBefore;
}

/// The consumed mapping is non-decreasing: no function can decrease consumed[user][group].
rule consumeNonDecreasing(env e, method f, calldataarg args, address user, bytes32 group) {
    uint256 consumedBefore = consumed(user, group);

    f(e, args);

    assert consumed(user, group) >= consumedBefore;
}

/// After a successful `take`, consumed[offer.maker][offer.group] does not exceed the effective max.
rule takeConsumedBoundedByMax(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert offer.maxSellerAssets > 0 => consumed(offer.maker, offer.group) <= offer.maxSellerAssets;
    assert offer.maxBuyerAssets > 0 => consumed(offer.maker, offer.group) <= offer.maxBuyerAssets;
    assert offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0 => consumed(offer.maker, offer.group) <= offer.maxUnits;
}

/// After a successful `take`, the change in consumed equals the units taken.
rule takeConsumedDelta(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0;

    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert consumed(offer.maker, offer.group) == consumedBefore + units;
}

/// If consumed[offer.maker][offer.group] is already at or above maxUnits before a `take` in units mode,
/// it remains unchanged.
rule takeConsumedAtMaxUnchangedUnits(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0;

    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert consumedBefore >= offer.maxUnits => consumed(offer.maker, offer.group) == consumedBefore;
}

/// If consumed is already at or above maxSellerAssets before a `take` in seller assets mode,
/// it remains unchanged.
rule takeConsumedAtMaxUnchangedSellerAssets(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.maxBuyerAssets == 0 && offer.maxUnits == 0;

    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert consumedBefore >= offer.maxSellerAssets => consumed(offer.maker, offer.group) == consumedBefore;
}

/// If consumed is already at or above maxBuyerAssets before a `take` in buyer assets mode,
/// it remains unchanged.
rule takeConsumedAtMaxUnchangedBuyerAssets(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.maxSellerAssets == 0 && offer.maxUnits == 0;

    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert consumedBefore >= offer.maxBuyerAssets => consumed(offer.maker, offer.group) == consumedBefore;
}

/// A fully-consumed offer in units mode only allows no-op takes.
rule fullyConsumedOfferRevertsOnNonTrivialTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0;

    uint256 consumedBefore = consumed(offer.maker, offer.group);

    require offer.maxUnits > 0 && consumedBefore >= offer.maxUnits, "assume the offer is fully consumed";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    // If take does not revert, its input has to be zero.
    assert units == 0;
}
