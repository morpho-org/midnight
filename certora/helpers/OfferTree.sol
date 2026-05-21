// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";

// Trees are built only via `newLeaf` and `newInternalNode`, which preserve well-formedness by construction.
// Leaves carry the offer payload so `isWellFormed` can pin a leaf's `hashNode` into the image of
// `hashOffer` (distinct keccak input shape from `hashNode`), giving domain separation against internal-node
// hashes for free under Certora's keccak model.
contract OfferTree {
    struct Node {
        bytes32 left;
        bytes32 right;
        Offer offer;
        bytes32 hashNode;
    }

    /* STORAGE */

    mapping(bytes32 => Node) internal tree;

    /* MAIN FUNCTIONS */

    function newLeaf(Offer memory offer) public {
        bytes32 id = HashLib.hashOffer(offer);
        require(id != 0, "id is the zero bytes");
        Node storage n = tree[id];
        require(_isEmpty(n), "leaf is not empty");
        n.offer = offer;
        n.hashNode = id;
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
    //   - empty nodes (left == 0 && right == 0 && hashNode == 0) are well-formed
    //   - leaves (left == 0 && right == 0 && hashNode != 0) require hashNode == hashOffer(offer) and id == hashNode
    //   - internal nodes (left != 0 && right != 0) require non-empty children and hashNode = hashNode(left.hashNode,
    // right.hashNode) - any other field combination is malformed
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (_isEmpty(n)) return true;
        if (n.left == 0 && n.right == 0) {
            bytes32 expected = HashLib.hashOffer(n.offer);
            return n.hashNode == expected && id == expected;
        }
        if (n.left != 0 && n.right != 0) {
            bytes32 leftHash = tree[n.left].hashNode;
            bytes32 rightHash = tree[n.right].hashNode;
            return leftHash != 0 && rightHash != 0 && n.hashNode == HashLib.hashNode(leftHash, rightHash);
        }
        return false;
    }

    // Check that the nodes are well-formed starting from `id` and going down the `tree`.
    // The bits of `leafIndex` choose the path downward; the depth is `proof.length`.
    function wellFormedPath(bytes32 id, uint256 leafIndex, bytes32[] memory proof) public view returns (bool) {
        for (uint256 i = proof.length;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            --i;
            id = ((leafIndex >> i) & 1 == 0) ? tree[id].left : tree[id].right;
        }
        return true;
    }
}
