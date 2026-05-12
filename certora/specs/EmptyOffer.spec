// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.emptyOffer() external returns (Midnight.Offer) envfree;

    // Summarize internals, which is sound since it would only remove revert reasons.
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
}

// Show that taking an empty offer always reverts.
// Useful for padding the offer tree with empty offers.
rule emptyOfferCantBeTaken(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, bytes ratifierData) {
    Midnight.Offer offer = Utils.emptyOffer();
    require e.block.timestamp > 0, "block.timestamp is always positive";
    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);
    assert lastReverted;
}
