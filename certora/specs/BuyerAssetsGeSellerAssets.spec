// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

}

/// buyerAssets >= sellerAssets.
rule buyerAssetsGeSellerAssets(
    env e,
    uint256 obligationShares,
    address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    Midnight.Offer offer, Midnight.Signature signature,
    bytes32 root, bytes32[] proof
) {

    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut = take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert buyerAssetsOut >= sellerAssetsOut;
}
