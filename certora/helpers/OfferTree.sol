// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

// Model of the binary tree of Offer hashes a wallet signs via EIP-712
// `OfferTree(Offer[2]...[2] offerTree)`. Wallet hashes raw concat
// (order-sensitive); on-chain `UtilsLib.isLeaf` uses commutative hashing
// (sort then keccak). The two coincide iff every internal pair satisfies
// `L.hash <= R.hash` — enforced by `isWellFormed`.
// Pattern adapted from morpho-org/URD's MerkleTree.sol.

struct Leaf {
    bytes32 offerHash;
}

struct InternalNode {
    bytes32 id;
    bytes32 left;
    bytes32 right;
}

struct Node {
    bytes32 left;
    bytes32 right;
    bytes32 offerHash;
    bytes32 hashNode;
}

contract OfferTree {
    mapping(bytes32 => Node) internal tree;

    function newLeaf(bytes32 id, Leaf memory leaf) external {
        Node storage node = tree[id];
        require(id != 0);
        require(isEmpty(node));
        require(leaf.offerHash != 0);
        node.offerHash = leaf.offerHash;
        // Wrap the leaf offerHash with an extra keccak (URD pattern) so
        // leaf hash inputs (32 bytes) are length-disjoint from internal
        // hash inputs (64 bytes). Cryptographically equivalent to
        // production's length-distinguishability via Offer-struct encoding;
        // here it makes the property provable under Certora's keccak model.
        node.hashNode = keccak256(bytes.concat(leaf.offerHash));
    }

    function newInternalNode(InternalNode memory ni) external {
        Node storage node = tree[ni.id];
        Node storage L = tree[ni.left];
        Node storage R = tree[ni.right];
        require(ni.id != 0);
        require(isEmpty(node));
        require(!isEmpty(L));
        require(!isEmpty(R));
        require(L.hashNode <= R.hashNode);
        node.left = ni.left;
        node.right = ni.right;
        node.hashNode = keccak256(abi.encode(L.hashNode, R.hashNode));
    }

    function isEmpty(Node memory n) public pure returns (bool) {
        return n.left == 0 && n.right == 0 && n.offerHash == 0 && n.hashNode == 0;
    }

    function isEmpty(bytes32 id) public view returns (bool) {
        return isEmpty(tree[id]);
    }

    function getHash(bytes32 id) external view returns (bytes32) {
        return tree[id].hashNode;
    }

    function getOfferHash(bytes32 id) external view returns (bytes32) {
        return tree[id].offerHash;
    }

    // (a) binary shape: 0 or 2 children with consistent hashing.
    // (b) pair-sorted: at every internal node, L.hash <= R.hash.
    // Leaf nodes wrap offerHash with `keccak(bytes.concat(...))` so leaf
    // hash inputs are length-disjoint from internal hash inputs.
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (isEmpty(n)) return true;
        if (n.left == 0 && n.right == 0) {
            return n.offerHash != 0
                && n.hashNode == keccak256(bytes.concat(n.offerHash));
        }
        if (n.left == 0 || n.right == 0) return false;
        Node storage L = tree[n.left];
        Node storage R = tree[n.right];
        return !isEmpty(L) && !isEmpty(R) && L.hashNode <= R.hashNode
            && n.hashNode == keccak256(abi.encode(L.hashNode, R.hashNode));
    }

    // Walks down from `id` using `proof` (consumed last-to-first), asserting
    // well-formedness at every visited node and requiring each proof
    // element to match one of the current node's child hashes. Returns
    // the leaf id reached.
    function wellFormedPathToLeaf(bytes32 id, bytes32[] memory proof)
        external
        view
        returns (bytes32)
    {
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));
            if (i == 0) break;
            bytes32 otherHash = proof[--i];
            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;
            bytes32 leftHash = tree[left].hashNode;
            bytes32 rightHash = tree[right].hashNode;
            require(otherHash == leftHash || otherHash == rightHash);
            id = leftHash == otherHash ? right : left;
        }
        return id;
    }

    // Single-frame forward-direction helper. Builds the wallet's EIP-712
    // root by sort-then-keccak at every level (= what well-formedness
    // produces) and runs production `UtilsLib.isLeaf` against it.
    function verifierAcceptsSortLabeledRoot(bytes32 leafHash, bytes32[] memory proof)
        external
        pure
        returns (bool)
    {
        bytes32 walletRoot = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 a = walletRoot;
            bytes32 b = proof[i];
            if (a > b) (a, b) = (b, a);
            bytes32 next;
            assembly ("memory-safe") {
                mstore(0x00, a)
                mstore(0x20, b)
                next := keccak256(0x00, 0x40)
            }
            walletRoot = next;
        }
        return UtilsLib.isLeaf(walletRoot, leafHash, proof);
    }

    // URD-style path condition. Reverts unless the commutative-hash chain
    // from the wrapped candidate offerHash with `proof` reaches `root`.
    // Uses the same `keccak256(bytes.concat(...))` leaf wrap and
    // `keccak256(abi.encode(L, R))` internal hash forms as tree storage
    // so the prover unifies hash terms across the chain and storage sides.
    function requireChainReaches(bytes32 root, bytes32 candidateOfferHash, bytes32[] memory proof)
        external
        pure
    {
        bytes32 current = keccak256(bytes.concat(candidateOfferHash));
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 a = current;
            bytes32 b = proof[i];
            if (a > b) (a, b) = (b, a);
            current = keccak256(abi.encode(a, b));
        }
        require(current == root);
    }

    // Boolean variant of `requireChainReaches`. Returns whether the chain
    // from the wrapped candidate offerHash with `proof` reaches `root`.
    function chainReaches(bytes32 root, bytes32 candidateOfferHash, bytes32[] memory proof)
        external
        pure
        returns (bool)
    {
        bytes32 current = keccak256(bytes.concat(candidateOfferHash));
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 a = current;
            bytes32 b = proof[i];
            if (a > b) (a, b) = (b, a);
            current = keccak256(abi.encode(a, b));
        }
        return current == root;
    }
}
