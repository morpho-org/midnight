// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

/// @dev Ghost offer-tree helper used by Certora specs.
/// @dev Trees are built only via `newLeaf` and `newInternalNode`, which preserve the
///      well-formedness invariant by construction. The verified invariant is then used
///      to prove that any successful `take` against a Midnight signed root corresponds
///      to a leaf actually present in the maker's tree.
/// @dev Purely structural: the helper does not encode the Offer struct itself, so it
///      avoids triggering pointer-analysis failures on `Offer.obligation.collateralParams[]`.
///      Specs supply leaf hashes externally (computed via the spec's chosen hashOffer
///      summary) and assert structural well-formedness here.
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
        require(L.hashNode <= R.hashNode, "children not pair-sorted");
        n.left = left;
        n.right = right;
        n.hashNode = UtilsLib.commutativeHash(L.hashNode, R.hashNode);
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
    ///      internal nodes have non-empty children, pair-sorted hashes, and
    ///      hashNode = commutativeHash(left.hashNode, right.hashNode).
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (_isEmpty(n)) return true;
        if (n.isLeaf) {
            return n.left == 0 && n.right == 0 && n.hashNode == id && n.hashNode != 0;
        } else {
            if (n.left == 0 || n.right == 0) return false;
            Node storage L = tree[n.left];
            Node storage R = tree[n.right];
            return !_isEmpty(L) && !_isEmpty(R) && L.hashNode <= R.hashNode
                && n.hashNode == UtilsLib.commutativeHash(L.hashNode, R.hashNode);
        }
    }

    /// @dev Walks down the tree from `id`, consuming `proof` from end to start,
    ///      asserting every visited node is well-formed AND that the path terminates
    ///      at a leaf.
    /// @dev At each step, descends into the child whose hash differs from the sibling
    ///      hash supplied in the proof. Mirrors the upward fold in `UtilsLib.isLeaf`.
    /// @dev The leaf-termination requirement encodes the assumption that `proof.length`
    ///      matches the actual depth from `id` to a leaf. The on-chain `take` does NOT
    ///      enforce this (it accepts any proof length whose folded hash equals root) —
    ///      the gap is intentional in the contract and is exposed by `takeCorrectness`
    ///      failing if this requirement is dropped.
    function wellFormedPath(bytes32 id, bytes32[] memory proof) public view {
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            bytes32 sibling = proof[--i];

            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;

            // Sibling must equal exactly one of the children's hashes. Without this,
            // the downward walk and the upward fold in `UtilsLib.isLeaf` can diverge
            // below the root, even though they agree on the root value: the fold
            // produces a synthetic intermediate hash unrelated to actual tree nodes,
            // and the spec's leaf-membership conclusion would not follow.
            require(getHash(left) == sibling || getHash(right) == sibling);

            id = getHash(left) == sibling ? right : left;
        }
        require(tree[id].isLeaf);
    }
}
