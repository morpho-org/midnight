// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x358117e98511cc3df97175dca58053b06675b43ad090b0553f8a1eff008b6e2e;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x6bd2a06ec6952feb97c3e3b4f7de6c342f12b1ac769d5c91368271af636c85b7;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xc27c38e446b48c820ab9c4373dc63a4a750a08165cb4bb488206ebabe045d650;
            if (height == 1) return 0x4e15d8736f4406e07bf9844b1653474472a827130c61e899bf1f574a88b8d987;
            if (height == 2) return 0x46d107447b480c38ef5b7f54603dba0cb23b887f302b01a998b9d8a80320dd53;
            if (height == 3) return 0xd1f3607a8e81454bb3baf5f898274ab47541fffc690278a74f13e174e116be72;
            if (height == 4) return 0xb2d98adca9d116c9bc02ce59ec599ac3c2d33db1c0d1217c7e411d9198d427be;
            if (height == 5) return 0x5931e0597fcf986027f3118b2495a9ac22139d133f9ad2c2198e6738dc3886c5;
            if (height == 6) return 0x3967d37928614a085b47e8758fbc3869a8aed63bdf60ccee8536ff2b5064da06;
            if (height == 7) return 0xd6b9f5f45915a260f6e521d9b40f86c385730b6bc330590fcde212e2fea64263;
            if (height == 8) return 0x080caa519dbd5328c119d9907e0fa3d9a50dc2ae4bf6dd42c93c100dbc89b51a;
            if (height == 9) return 0x45da471048924165ea2ad1855ba940e454b486e71dcf1666c71a928c8844c419;
            return 0xa49a9434fc1836bd08097368325b31039b6a0fd44919f53e4d8f4bf814084cb0;
        } else {
            if (height == 11) return 0xd3e93e4525132f0187a6964dc01fef33fde414538ffd212e9f2f478c3263e0a0;
            if (height == 12) return 0x25990db2d26547f92c711988300df317af57bad5cd5d9d8e787a82f95c929474;
            if (height == 13) return 0x8e0c648afa977572ead40a1d10a6db2c425b8099545006d834a7b849c6166643;
            if (height == 14) return 0x4b635250efa6243e277fdd0cf6df993c2943b64f10f3a0756ceb1f47ef8f9b18;
            if (height == 15) return 0xbde1c927f6222c07c8df264e68b42b8382c7c2b85f4729e0df94297cfeebfa91;
            if (height == 16) return 0x4d58aea1a67f94be21ab1415bf3b602592430eb9112268fd0fc4e141b1a35e76;
            if (height == 17) return 0x14c03281bce13010b158e5a4a3378be394ac9e16118aedb17d82ced51e66836c;
            if (height == 18) return 0x99fd3e76f43b2cc221cb9860bc6c96cda95af3fa07ef5f04e071b54aa9386d06;
            if (height == 19) return 0x1b1c2f1a04968094d8d0453d49838f7a809d1202ae04a1c2e0964e442ff7988b;
            if (height == 20) return 0xc8ccd3cb3267dd76f563584920ac60f2283b719917481b85fe5e10b754932455;
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
