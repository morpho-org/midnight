// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes20 id, address user) external returns (uint256) envfree;

    function _.price() external => PER_CALLEE_CONSTANT;

    function _.onBuy(MorphoV2.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(MorphoV2.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}


/// In take, only the seller can newly become a borrower; the buyer can only reduce debt.
rule takeOnlySellerBecomesBorrower(
    env e, uint256 buyerAssets, uint256 sellerAssets,
    uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2.Offer offer, MorphoV2.Signature signature,
    bytes32 root, bytes32[] proof,
    bytes20 id, address user
) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    uint256 debtBefore = debtOf(id, user);

    take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    uint256 debtAfter = debtOf(id, user);

    // Buyer can only reduce debt
    assert user == buyer => debtAfter <= debtBefore;
    // Seller can only increase debt
    assert user == seller => debtAfter >= debtBefore;
    // Third parties can't change debt
    assert user != buyer && user != seller => debtAfter == debtBefore;
}
