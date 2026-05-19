// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";

/// @dev Ghost offer-tree helper used by Certora specs.
/// @dev Trees are built only via `newLeaf` and `newInternalNode`, which preserve the
///      well-formedness invariant by construction. The verified invariant is then used
///      to prove that any successful merkle proof verification against a Midnight
///      ratified root corresponds to a leaf actually present in the maker's tree.
/// @dev Purely structural: the helper does not encode the Offer struct itself, so it
///      avoids triggering pointer-analysis failures on `Offer.market.collateralParams[]`.
///      Specs supply leaf hashes externally (computed via the spec's chosen hashOffer
///      summary) and assert structural well-formedness here.
/// @dev Mirrors the post-merge `HashLib.isLeaf` proof scheme: internal nodes have
///      directional left/right children combined via `HashLib.hashNode`, and the
///      downward walk in `wellFormedPath` follows the bits of `leafIndex`.
contract OfferTree {
    struct Node {
        bytes32 left;
        bytes32 right;
        bytes32 hashNode;
        bool isLeaf;
    }

    mapping(bytes32 => Node) internal tree;

    function newLeaf(bytes32 leafHash) public {
        require(leafHash != 0, "zero leaf hash");
        Node storage n = tree[leafHash];
        require(_isEmpty(n), "leaf already populated");
        n.hashNode = leafHash;
        n.isLeaf = true;
    }

    function newInternalNode(bytes32 id, bytes32 left, bytes32 right) public {
        require(id != 0, "zero id");
        Node storage n = tree[id];
        require(_isEmpty(n), "node already populated");
        Node storage L = tree[left];
        Node storage R = tree[right];
        require(!_isEmpty(L), "left empty");
        require(!_isEmpty(R), "right empty");
        n.left = left;
        n.right = right;
        n.hashNode = HashLib.hashNode(L.hashNode, R.hashNode);
    }

    function _isEmpty(Node storage n) internal view returns (bool) {
        return n.left == 0 && n.right == 0 && n.hashNode == 0 && !n.isLeaf;
    }

    function isEmpty(bytes32 id) public view returns (bool) {
        return _isEmpty(tree[id]);
    }

    function getHash(bytes32 id) public view returns (bytes32) {
        return tree[id].hashNode;
    }

    function isLeafNode(bytes32 id) public view returns (bool) {
        return tree[id].isLeaf;
    }

    function getLeft(bytes32 id) public view returns (bytes32) {
        return tree[id].left;
    }

    function getRight(bytes32 id) public view returns (bytes32) {
        return tree[id].right;
    }

    /// @dev Well-formed predicate.
    /// @dev Empty nodes well-formed; leaves have id == hashNode and no children;
    ///      internal nodes have non-empty children and hashNode = hashNode(left.hashNode, right.hashNode).
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (_isEmpty(n)) return true;
        if (n.isLeaf) {
            return n.left == 0 && n.right == 0 && n.hashNode == id && n.hashNode != 0;
        } else {
            if (n.left == 0 || n.right == 0) return false;
            Node storage L = tree[n.left];
            Node storage R = tree[n.right];
            return !_isEmpty(L) && !_isEmpty(R)
                && n.hashNode == HashLib.hashNode(L.hashNode, R.hashNode);
        }
    }

    /// @dev Walks down the tree from `id`, consuming `proof` from end to start,
    ///      asserting every visited node is well-formed AND that the path terminates
    ///      at a leaf.
    /// @dev At each level, the bit of `leafIndex` decides which side the leaf descends to,
    ///      mirroring the upward fold in `HashLib.isLeaf`:
    ///        bit == 0 ⇒ leaf was on the LEFT (sibling is the right child).
    ///        bit == 1 ⇒ leaf was on the RIGHT (sibling is the left child).
    /// @dev The leaf-termination requirement encodes the assumption that `proof.length`
    ///      matches the actual depth from `id` to a leaf. The on-chain `HashLib.isLeaf` does
    ///      NOT enforce this (it accepts any proof length whose folded hash equals root) —
    ///      the gap is intentional in the contract and is exposed by `takeCorrectness`
    ///      failing if this requirement is dropped.
    function wellFormedPath(bytes32 id, uint256 leafIndex, bytes32[] memory proof) public view {
        require(leafIndex >> proof.length == 0, "leaf index out of range");
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            // If we still have proof elements to consume, the current node must be an
            // internal node, not a leaf. Without this, the prover can pick a leaf as the
            // starting node — `isWellFormed` accepts it via the leaf branch, the loop
            // walks off the leaf's zero children into the unrelated `tree[0]` entry, and
            // the well-formedness chain that should pin `hashOffer(offer)` to a leaf in
            // this subtree is never established, since the leaf branch of `isWellFormed`
            // generates no `hashNode(L.hashNode, R.hashNode)` equation tying the root
            // hash to the merkle fold.
            require(!tree[id].isLeaf);

            bytes32 sibling = proof[--i];

            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;

            // The sibling supplied by the proof must equal the corresponding child's
            // stored hash. Without this, the downward walk and the upward fold in
            // `HashLib.isLeaf` can diverge below the root, even though they agree on
            // the root value: the fold produces a synthetic intermediate hash unrelated
            // to actual tree nodes, and the spec's leaf-membership conclusion would not
            // follow.
            if ((leafIndex >> i) & 1 == 0) {
                require(getHash(right) == sibling);
                id = left;
            } else {
                require(getHash(left) == sibling);
                id = right;
            }
        }
        require(tree[id].isLeaf);
    }
}
