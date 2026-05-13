// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

// Model of the binary tree of Offer hashes a wallet signs via EIP-712
// `OfferTree(Offer[2]...[2] offerTree)`. Wallet hashes raw concat
// (order-sensitive); on-chain `UtilsLib.isLeaf` uses commutative hashing
// (sort then keccak). The two coincide iff every internal pair satisfies
// `L.hash <= R.hash` — enforced by `isWellFormed`.
//
// `Leaf.offerHash` stands in for production's `UtilsLib.hashOffer(offer)`.
// Leaves are represented by that raw bytes32 directly; no extra wrapper
// hash around the leaf.

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
        node.hashNode = leaf.offerHash;
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

    // (a) binary shape: 0 or 2 children with consistent hashing.
    // (b) pair-sorted: at every internal node, L.hash <= R.hash.
    // (c) internal nodes carry no offerHash; leaf nodes store offerHash
    //     raw, matching production `UtilsLib.hashOffer` directly.
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (isEmpty(n)) return true;
        if (n.left == 0 && n.right == 0) {
            return n.offerHash != 0 && n.hashNode == n.offerHash;
        }
        if (n.left == 0 || n.right == 0) return false;
        Node storage L = tree[n.left];
        Node storage R = tree[n.right];
        return n.offerHash == 0 && !isEmpty(L) && !isEmpty(R)
            && L.hashNode <= R.hashNode
            && n.hashNode == keccak256(abi.encode(L.hashNode, R.hashNode));
    }

    // Single-frame soundness helper. Walks `proof` downward from `rootId`,
    // asserting well-formedness at every node and threading the EXPECTED
    // hash from root to leaf via the commutative combiner. Path conditions:
    //   - each proof entry must match one of the visited node's child hashes;
    //   - the walked-to id must be a leaf;
    //   - the final expected leaf hash must equal `candidateOfferHash`
    //     (i.e. the chain accepts the candidate against the stored root).
    // Returns whether the candidate equals the stored offerHash at the
    // reached leaf. The rule asserts this returns true — i.e. no candidate
    // other than the stored one can satisfy the path condition.
    //
    // Threading the expected hash downward (rather than reconstructing the
    // chain upward in a second pass) keeps all hash equalities in one
    // symbolic frame, which Certora's keccak modeling can unify.
    function acceptedCandidateMatchesStoredLeaf(
        bytes32 rootId,
        bytes32[] memory proof,
        bytes32 candidateOfferHash
    ) external view returns (bool) {
        bytes32 id = rootId;
        bytes32 expected = tree[rootId].hashNode;
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));
            require(tree[id].hashNode == expected);
            if (i == 0) break;
            bytes32 otherHash = proof[--i];
            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;
            bytes32 leftHash = tree[left].hashNode;
            bytes32 rightHash = tree[right].hashNode;
            require(otherHash == leftHash || otherHash == rightHash);
            bytes32 childHash;
            if (leftHash == otherHash) {
                id = right;
                childHash = rightHash;
            } else {
                id = left;
                childHash = leftHash;
            }
            bytes32 a = childHash;
            bytes32 b = otherHash;
            if (a > b) (a, b) = (b, a);
            require(expected == keccak256(abi.encode(a, b)));
            expected = childHash;
        }
        require(tree[id].left == 0 && tree[id].right == 0);
        require(tree[id].offerHash != 0);
        require(expected == candidateOfferHash);
        return candidateOfferHash == tree[id].offerHash;
    }

    // Single-frame faithfulness bridge between the modeled hashing form
    // `keccak256(abi.encode(a, b))` used by the storage tree and the
    // production primitive `UtilsLib.commutativeHash(a, b)`. Both compute
    // keccak over the same 64-byte sorted pair; this helper exposes them
    // side by side so a CVL rule can assert equality within one symbolic
    // frame and close the model-vs-production gap.
    function sortedPairHashEquivalence(bytes32 a, bytes32 b)
        external
        pure
        returns (bool sorted, bool equal)
    {
        sorted = a <= b;
        equal = keccak256(abi.encode(a, b)) == UtilsLib.commutativeHash(a, b);
    }
}
