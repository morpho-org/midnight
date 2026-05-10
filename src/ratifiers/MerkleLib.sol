// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE, OFFER_TYPE} from "../libraries/ConstantsLib.sol";

/// @dev Helpers for verifying signed Merkle trees of offers.
library MerkleLib {
    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        bytes memory offerTreeType = "OfferTree(Offer";
        for (uint256 i = 0; i < height; i++) {
            offerTreeType = bytes.concat(offerTreeType, "[2]");
        }
        offerTreeType = bytes.concat(offerTreeType, " offerTree)");
        return keccak256(bytes.concat(offerTreeType, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE, OFFER_TYPE));
    }

    /// @dev Returns hash(... hash(leafHash, proof[0]), ..., proof[n]) == root.
    /// @dev Hash sorts the inputs lexicographically.
    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] memory proof) internal pure returns (bool) {
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = commutativeHash(currentHash, proof[i]);
        }
        return currentHash == root;
    }

    /// @dev Returns the keccak256 hash of the sorted concatenation of a and b.
    function commutativeHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        if (a > b) (a, b) = (b, a);
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
