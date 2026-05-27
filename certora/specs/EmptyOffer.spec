// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.emptyOffer() external returns (Midnight.Offer) envfree;

    // Summarize internals, which is sound since it would only remove revert reasons.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
}

// Show that taking an empty offer always reverts.
// Useful for padding the offer tree with empty offers.
rule emptyOfferCantBeTaken(env e, bytes ratifierData, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller) {
    Midnight.Offer offer = Utils.emptyOffer();
    require e.block.timestamp > 0, "block.timestamp is always positive";
    take@withrevert(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    assert lastReverted;
}
