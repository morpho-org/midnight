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
    }

    /* STORAGE */

    mapping(bytes32 => Node) internal tree;

    /* MAIN FUNCTIONS */

    function newLeaf(bytes32 leafHash) public {
        require(leafHash != 0, "zero leaf hash");
        Node storage n = tree[leafHash];
        require(_isEmpty(n), "leaf already populated");
        n.hashNode = leafHash;
    }

    function newInternalNode(bytes32 id, bytes32 left, bytes32 right) public {
        require(id != 0, "zero id");
        Node storage n = tree[id];
        require(_isEmpty(n), "node already populated");
        bytes32 leftHash = tree[left].hashNode;
        bytes32 rightHash = tree[right].hashNode;
        require(leftHash != 0, "left empty");
        require(rightHash != 0, "right empty");
        n.left = left;
        n.right = right;
        n.hashNode = HashLib.hashNode(leftHash, rightHash);
    }

    /* PURE AND VIEW FUNCTIONS */

    function _isEmpty(Node storage n) internal view returns (bool) {
        return n.left == 0 && n.right == 0 && n.hashNode == 0;
    }

    function isEmpty(bytes32 id) public view returns (bool) {
        return _isEmpty(tree[id]);
    }

    function getHash(bytes32 id) public view returns (bytes32) {
        return tree[id].hashNode;
    }

    function isLeafNode(bytes32 id) public view returns (bool) {
        return tree[id].left == 0 && tree[id].right == 0 && tree[id].hashNode != 0;
    }

    function getLeft(bytes32 id) public view returns (bytes32) {
        return tree[id].left;
    }

    function getRight(bytes32 id) public view returns (bytes32) {
        return tree[id].right;
    }

    // The specification of a well-formed tree is the following:
    //   - empty nodes (all fields zero) are well-formed
    //   - leaves (left == 0 && right == 0 && hashNode != 0) require hashNode == id
    //   - internal nodes (left != 0 && right != 0) require non-empty children and hashNode = hashNode(left.hashNode, right.hashNode)
    //   - any other field combination is malformed
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (_isEmpty(n)) return true;
        if (n.left == 0 && n.right == 0) {
            return n.hashNode == id;
        }
        if (n.left != 0 && n.right != 0) {
            bytes32 leftHash = tree[n.left].hashNode;
            bytes32 rightHash = tree[n.right].hashNode;
            return leftHash != 0 && rightHash != 0
                && n.hashNode == HashLib.hashNode(leftHash, rightHash);
        }
        return false;
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

            // If proof elements remain, the current node must be internal; otherwise the path walks off a leaf's zero
            // children into the unrelated `tree[0]` entry.
            require(!isLeafNode(id));

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
        require(isLeafNode(id));
        return id;
    }
}
