// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

/// @dev Verifies proofs of trees built with sorted-pair hashing and double-hashed leaves, which is the layout of
/// OpenZeppelin's StandardMerkleTree, so standard off-chain tooling produces compatible roots and proofs.
library MerkleProofLib {
    /// @dev Returns the leaf of a `(address, uint256)` entry.
    function leaf(address account, uint256 value) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, value))));
    }

    function verify(bytes32[] memory proof, bytes32 root, bytes32 leafHash) internal pure returns (bool) {
        bytes32 computed = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            computed = computed < sibling
                ? keccak256(bytes.concat(computed, sibling))
                : keccak256(bytes.concat(sibling, computed));
        }
        return computed == root;
    }
}
