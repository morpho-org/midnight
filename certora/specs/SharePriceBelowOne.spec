// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    // Summaries to avoid SMT solver timeout.
    function tradingFee(bytes20, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
}

// Share/asset ratio is never above 1: totalShares >= totalUnits at all times.

strong invariant sharePriceBelowOrEqOne1(bytes20 id)
    totalShares(id) >= totalUnits(id)
{
    preserved take(uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        MorphoV2.Offer offer,
        MorphoV2.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
            require buyerAssets != 0 && sellerAssets == 0 && obligationUnits == 0 && obligationShares == 0, "other cases checked separately";
            require buyerAssets < 2^128;
        }
}


strong invariant sharePriceBelowOrEqOne2(bytes20 id)
    totalShares(id) >= totalUnits(id)
{
    preserved take(uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        MorphoV2.Offer offer,
        MorphoV2.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
            require buyerAssets == 0 && sellerAssets != 0 && obligationUnits == 0 && obligationShares == 0, "other cases checked separately";
            require sellerAssets < 2^128;
        }
}

strong invariant sharePriceBelowOrEqOne3(bytes20 id)
    totalShares(id) >= totalUnits(id)
{
    preserved take(uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        MorphoV2.Offer offer,
        MorphoV2.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
            require buyerAssets == 0 && sellerAssets == 0 && obligationUnits != 0 && obligationShares == 0, "other cases checked separately";
        }
}

strong invariant sharePriceBelowOrEqOne4(bytes20 id)
    totalShares(id) >= totalUnits(id)
{
    preserved take(uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        MorphoV2.Offer offer,
        MorphoV2.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
            require buyerAssets == 0 && sellerAssets == 0 && obligationUnits == 0, "other cases checked separately";
        }
}
