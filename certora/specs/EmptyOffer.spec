// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using Utils as Utils;

methods {
    function Utils.emptyOffer() external returns (Midnight.Offer) envfree;

    // Summarize internals, which is sound since it would only remove revert reasons.
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Explicit HAVOC_ECF so -havocAllByDefault does not summarize these as HAVOC_ALL.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => HAVOC_ECF;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => HAVOC_ECF;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => HAVOC_ECF;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => HAVOC_ECF;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => HAVOC_ECF;

    // Views stay NONDET. -havocAllByDefault would otherwise summarize them as HAVOC_ALL.
    function _.price() external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
}

// Show that taking an empty offer always reverts.
// Useful for padding the offer tree with empty offers.
rule emptyOfferCantBeTaken(env e, bytes ratifierData, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller) {
    Midnight.Offer offer = Utils.emptyOffer();
    require e.block.timestamp > 0, "block.timestamp is always positive";
    take@withrevert(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    assert lastReverted;
}
