// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0x39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0xc7217937e3e4792f008803233f9ab5733ae21550dfd9a82f7a931202d8519182;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0xbe02458b8446cb4d08b43541761ff65d260a0247247652479c648e920469de95;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x3ee1994da955d5aa3e32de9e53261da443a2406198e3fc5d504c7e8b2a947953;
            if (height == 1) return 0xc658b2e55d2e8a0383982564366d7008a7a0743863c09905382e17de18409edb;
            if (height == 2) return 0x4e0adcc9afd3d2080aac34120ed811e21a333779a62906005c2379e3f69eead2;
            if (height == 3) return 0x7dc62fe405e0f2bb86f8aa4917949a80f9a43b0533439da84befc5f86db9f8b8;
            if (height == 4) return 0x827956f8aafdb5e1977c15463f7acf66574e20f7816c609330a1c384d5d8f676;
            if (height == 5) return 0xebb0c1d27456093ca3da34dda5806074909dd149beee083cc5773693bd2173e2;
            if (height == 6) return 0x7762fbf5c7a7ace0fba4c779124cb4d3eb2e36dfca7b69db8c58e7cc338f06f3;
            if (height == 7) return 0xee68d4c6dbc5ebd3f2a2b888e1e8183e9c3e2abb5f6b11ae29c7f9e4e2f1bd08;
            if (height == 8) return 0x51a23c87d840ec3998fa1ca65c8252b77695e334d86da192578ac27e10904963;
            if (height == 9) return 0x0118309844ce8ed678b69710edade8185443a49bb39b2fe3be46a0df1c73c41a;
            return 0x95ee7bf616c256f973563b7bcd7ac6711b569fe4dd8c059518e1c61ea542bf63;
        } else {
            if (height == 11) return 0x0a09bd2194e87e661b564b9a3a60f18a3d1558f63c51ea3b7668d69b52b34c85;
            if (height == 12) return 0x7658b4c053abc5076abe87bde4846e9c74001d8173009ec166fe69fab803605b;
            if (height == 13) return 0x60fa6620ed4ae28578399b4eb8900145883babafaf5e0b7b88f105b5873cbf22;
            if (height == 14) return 0x2ff0610678245028de334e1bf7de8191b7c2d2cadd004a545134f2e585461dbf;
            if (height == 15) return 0xa45443482c81a668a9119c2659c87fa22f66c89528237a86b8c8c6997f85f81f;
            if (height == 16) return 0x400c36ea65fc9f5d0d018fbc2877a8eed7ba4ed735d2b0f791621a8652598043;
            if (height == 17) return 0x23cbda45134146dc786abd8f7cf5efab3a10f0419d7087a35211f62082c64be7;
            if (height == 18) return 0x3be9250a943a7ae0c1ce9e807b89fa4d49752a9f5c4cc195e7c9560e49072e0e;
            if (height == 19) return 0xb50a451161608cb6216239dcccb61dd9b3da0c7aa2e607f69c8295aec6b859e2;
            if (height == 20) return 0x25c08c52eda13f831fa57fcd45bb0d89b84222c44e77e658fb58687a6cd6ebd5;
            revert TreeTooHigh();
        }
    }

    /// @dev Verifies a Merkle proof using the leaf index to determine the left/right position of each sibling.
    /// @dev Works for offer-tree heights up to 256, the bit-width of leafIndex.
    function isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof)
        internal
        pure
        returns (bool)
    {
        require(leafIndex >> proof.length == 0, LeafIndexOutOfRange());
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = (leafIndex >> i) & 1 == 0 ? hashNode(currentHash, proof[i]) : hashNode(proof[i], currentHash);
        }
        return currentHash == root;
    }

    /// @dev Returns the keccak256 hash of the concatenation of left and right.
    function hashNode(bytes32 left, bytes32 right) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, left)
            mstore(0x20, right)
            value := keccak256(0x00, 0x40)
        }
    }

    /// @dev Computes the EIP-712 hash struct of a CollateralParams.
    function hashCollateralParams(CollateralParams memory collateralParams) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COLLATERAL_PARAMS_TYPEHASH,
                collateralParams.token,
                collateralParams.lltv,
                collateralParams.liquidationCursor,
                collateralParams.oracle
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of a Market.
    function hashMarket(Market memory market) internal pure returns (bytes32) {
        bytes32[] memory collateralParamsHashes = new bytes32[](market.collateralParams.length);
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            collateralParamsHashes[i] = hashCollateralParams(market.collateralParams[i]);
        }

        bytes32 collateralParamsHash;
        // same as keccak256(abi.encodePacked(collateralParamsHashes));
        assembly ("memory-safe") {
            collateralParamsHash := keccak256(
                add(collateralParamsHashes, 0x20),
                mul(mload(collateralParamsHashes), 0x20)
            )
        }

        return keccak256(
            abi.encode(
                MARKET_TYPEHASH,
                market.loanToken,
                collateralParamsHash,
                market.maturity,
                market.rcfThreshold,
                market.enterGate,
                market.liquidatorGate
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of an Offer.
    function hashOffer(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                hashMarket(offer.market),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                offer.tick,
                offer.group,
                offer.callback,
                keccak256(offer.callbackData),
                offer.receiverIfMakerIsSeller,
                offer.ratifier,
                offer.reduceOnly,
                offer.maxUnits,
                offer.maxAssets,
                offer.continuousFeeCap
            )
        );
    }
}
