// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";

// Ghost offer-tree helper used by Certora specs.
// Trees are built only via `newLeaf` and `newInternalNode`, which preserve well-formedness by construction.
// Specs supply leaf hashes externally; the helper does not encode the Offer struct itself.
contract OfferTree {
    struct Node {
        bytes32 left;
        bytes32 right;
        bytes32 hashNode;
        bool isLeaf;
    }

    /* STORAGE */

    mapping(bytes32 => Node) internal tree;

    /* MAIN FUNCTIONS */

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

    /* PURE AND VIEW FUNCTIONS */

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

    // The specification of a well-formed tree is the following:
    //   - empty nodes are well-formed
    //   - leaves have id == hashNode and no children
    //   - internal nodes have non-empty children and hashNode = hashNode(left.hashNode, right.hashNode)
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

    // Check that the nodes are well-formed starting from `id` and going down the `tree`.
    // The bits of `leafIndex` choose the path downward; `proof` supplies the sibling hashes consumed from end to start.
    // The path must terminate at a leaf, matching the depth implied by `proof.length`.
    // Returns the id of the leaf at the bottom of the path.
    function wellFormedPath(bytes32 id, uint256 leafIndex, bytes32[] memory proof) public view returns (bytes32) {
        require(leafIndex >> proof.length == 0, "leaf index out of range");
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            // If proof elements remain, the current node must be internal; otherwise the path walks off a leaf's zero children into the unrelated `tree[0]` entry.
            require(!tree[id].isLeaf);

            bytes32 sibling = proof[--i];

            bytes32 left = tree[id].left;
            bytes32 right = tree[id].right;

            if ((leafIndex >> i) & 1 == 0) {
                require(getHash(right) == sibling);
                id = left;
            } else {
                require(getHash(left) == sibling);
                id = right;
            }
        }
        require(tree[id].isLeaf);
        return id;
    }
}
