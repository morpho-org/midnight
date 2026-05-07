// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

/// @dev Ghost offer-tree helper used by Certora specs.
/// @dev Trees are built only via `newLeaf` and `newInternalNode`, which preserve the
///      well-formedness invariant by construction. The verified invariant is then used
///      to prove that any successful `take` against a Midnight signed root corresponds
///      to a leaf actually present in the maker's tree.
contract OfferTree {
    struct Node {
        bytes32 left;
        bytes32 right;
        bytes32 hashNode;
        bool isLeaf;
    }

    mapping(bytes32 => Node) internal tree;

    function newLeaf(Offer memory offer) public {
        bytes32 h = UtilsLib.hashOffer(offer);
        require(h != 0, "zero leaf hash");
        Node storage n = tree[h];
        require(_isEmpty(n), "leaf already populated");
        n.hashNode = h;
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

    function hashOffer(Offer memory offer) external pure returns (bytes32) {
        return UtilsLib.hashOffer(offer);
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
    ///      asserting every visited node is well-formed.
    /// @dev At each step, descends into the child whose hash differs from the sibling
    ///      hash supplied in the proof. Mirrors the upward fold in `UtilsLib.isLeaf`.
    function wellFormedPath(bytes32 id, bytes32[] memory proof) public view {
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            bytes32 sibling = proof[--i];

            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;

            id = getHash(left) == sibling ? right : left;
        }
    }
}
