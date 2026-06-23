// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x9726017d91c6ee720433cc66705fc8e73c66a5b54318610634e0615c1050c039;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x36b9157a5f6ca813c3e19022b1ae38bcc92474337a2905509648965b6bb25b92;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xf060e448a16febf6d574124babc538caa4e2b16b7d984b9a43138450fff6e487;
            if (height == 1) return 0xdb7fcde9ede9a072d4b90099b7d70d3b078b8bd68eb7ebd656a7377363ac16e7;
            if (height == 2) return 0x685d7c4569230738727c18fe3466e230e88e3910efa807662f1ace69be578cf8;
            if (height == 3) return 0xc7447f9389248ec66fb8e2da0f33f2a75f14d028a260253ebd269062964a0ff0;
            if (height == 4) return 0xdb2881d2334835a88923d1750f18f66230be7ad26cf6e365b8b66573a488f758;
            if (height == 5) return 0xf998c5d024660a141601215a4c840a1e93cb734577da1f536f2e309eab9daa62;
            if (height == 6) return 0x1a1546d3ee2cdcb87df2ba14cc402269536c5eb1a058559eea6b20b33886fec1;
            if (height == 7) return 0xb970a1682bb961ff3038be80f6f0aa47a27ba955017ef22e1692da56a6fd583e;
            if (height == 8) return 0xf44dac05caf7ffd668d73b72ba37867a3ed437ef625cfb517749609ab3e99683;
            if (height == 9) return 0x8cd5c1d1c9277864113deaf1b2459d6688762fae010b3a6fd4ddd5befb85cf12;
            return 0xebc93f3cf5dec43925a753dde4ca54c3615b34688066417d28200bd8c1ba7b5a;
        } else {
            if (height == 11) return 0x0c284c1a76381ce275f1394cd25f795fd7f331e06dec54d7eed31d7092c1fbc8;
            if (height == 12) return 0x2ac3bffae03e78dd4603a0e8702488b52bc2fa271b5e27cd58cd84f7bcc57e6a;
            if (height == 13) return 0x42b99a1129d92a79d6757afb25f893eff4f31a3fb550be942b8abc31be8d4ace;
            if (height == 14) return 0xdc8ec2491b7d8a693bd943aa90f544bcc3d03bdbf4ca11effc5ad64f5a54761e;
            if (height == 15) return 0x6079f350a9f94248af09b389dde6562618f19dae07095660978985dc3767f683;
            if (height == 16) return 0x8b2ea640243d598efc46c59303ff8853b43e9150ca72cb9bdd42bcb4a3e1e13c;
            if (height == 17) return 0xbfadafebb38539f93a87280ecbc0dddf246a91a5bb6f279ab13e2dda19e1c639;
            if (height == 18) return 0x9f1c3865762ee804df5d75220040b2164dfcd8ca336af4a0645a12fdbbbaf765;
            if (height == 19) return 0x0d7255859b43f915c7eb1c6001be9a750c1bd2f9bc55528a97029143770dda95;
            if (height == 20) return 0xf6ff0d681e5c27abedfcc9572b58e1c8314950e031448ee4954dc2573e3ff889;
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
                collateralParams.maxLif,
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
                market.midnight,
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
