// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x358117e98511cc3df97175dca58053b06675b43ad090b0553f8a1eff008b6e2e;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x37506ae960bd1ee59f5ab2dbd0c1ed8f9b5fbce861155185dcf57b4dae1ed806;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xeb3f50577f098116361b11b1bbc1132b57ce752e28662540768c9202b7da8e79;
            if (height == 1) return 0x1b534886acd069eb4bfb25c4e808fe44111b83fc996534841ea39936a2c644c8;
            if (height == 2) return 0xd52b3e9c171afe62b4a7ef18722c1a3426769b795f5a00753e0f3c82fc4e9242;
            if (height == 3) return 0x30013cd7bd61d8940482ca5c36f334164043f405680950568428c16d3b2f79b4;
            if (height == 4) return 0x042232b53c70701f7de1e13ef6e06deb8efd311b0bd4afb5dc7f398c46536abe;
            if (height == 5) return 0x8d885f558a38b3ac8a8167b6948e20704445d3a50bf1a3bd6fb612733a6a139c;
            if (height == 6) return 0x490cf3e82aa1440daa960f07bd892aa17cc3dbf43d499fed9b5d7432e76dc4c6;
            if (height == 7) return 0x45042cabfb9d41706c3e633df6058cd235aee2ed2cef96c7ffb11f575c0e3d75;
            if (height == 8) return 0xd487e443cbd35469a9c6b23417c56eef45cc6b647597414799e8a773d1af82b0;
            if (height == 9) return 0x6f007ea0c225b44afe84f1d6239f57b918022b0c4efc56190626427a3545bea4;
            return 0x5552efc3ebec05564da399299980f1989114d55ab4f15c55d7c7ab13d96747c5;
        } else {
            if (height == 11) return 0x5cd4011f887ef0adca39577933ee87883bcb764d6158c4e61d0ac232939ed112;
            if (height == 12) return 0x4f7029a032cb432e7f76cc66e09c960c43f0202fa1123b172696bbddbd793a41;
            if (height == 13) return 0xd4808138b3d27ffed3eeea1d4256263c7107bfa7469696842774531db829eb2c;
            if (height == 14) return 0x261e3f5411f1f213ee0d75885492786508455b3fc35323fdb9e15a4aa066951e;
            if (height == 15) return 0x233612f28095cd987952c83314568e077d879332f1828efa67fe5d0d4f657d00;
            if (height == 16) return 0xa709f9f47f644039570fb065fc154bc778c6eebfa88519ac6f0c39d7971d66fc;
            if (height == 17) return 0xfd2a3aa54ed6836739be6dcba53282de4be82b38f2a06f16283fd90a406727fd;
            if (height == 18) return 0x48d24eca0e5fccba484a2d406e47be0b8a83474286093befa6b3449a051411c6;
            if (height == 19) return 0x706209d07a74d59d2475c4a74b0b6d9cec8f69068f43b5642f44202300bbd20e;
            if (height == 20) return 0xe1cc846c902c4c561f4f244bb9bb0d7da9a8089e0c1acb01f4151537b05a7ffc;
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
                offer.maxContinuousFee
            )
        );
    }
}
