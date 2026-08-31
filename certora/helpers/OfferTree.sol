// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib, OFFER_TYPEHASH} from "../../src/ratifiers/libraries/HashLib.sol";

// Fixed-size pre-image of HashLib.hashOffer. Dynamic fields are stored as hashes so CVL can re-hash a leaf
// without iterating over dynamic data.
struct Leaf {
    bytes32 marketHash; // = HashLib.hashMarket(offer.market)
    bool buy;
    address maker;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    address callback;
    bytes32 callbackDataHash; // = keccak256(offer.callbackData)
    address receiverIfMakerIsSeller;
    address ratifier;
    bool reduceOnly;
    uint256 maxUnits;
    uint256 maxAssets;
    uint256 continuousFeeCap;
}

contract OfferTree {
    struct Node {
        bytes32 left;
        bytes32 right;
        Leaf leaf;
        // Offer hash for leaves and hash of the children for internal nodes.
        bytes32 hashNode;
    }

    // Leaf ids are offer hashes. Internal node ids may be arbitrary.
    mapping(bytes32 => Node) internal tree;

    function newLeaf(Offer memory offer) public {
        bytes32 id = HashLib.hashOffer(offer);
        require(id != 0, "id is the zero bytes");
        Node storage n = tree[id];
        require(_isEmpty(n), "leaf is not empty");
        Leaf storage l = n.leaf;
        l.marketHash = HashLib.hashMarket(offer.market);
        l.buy = offer.buy;
        l.maker = offer.maker;
        l.start = offer.start;
        l.expiry = offer.expiry;
        l.tick = offer.tick;
        l.group = offer.group;
        l.callback = offer.callback;
        l.callbackDataHash = keccak256(offer.callbackData);
        l.receiverIfMakerIsSeller = offer.receiverIfMakerIsSeller;
        l.ratifier = offer.ratifier;
        l.reduceOnly = offer.reduceOnly;
        l.maxUnits = offer.maxUnits;
        l.maxAssets = offer.maxAssets;
        l.continuousFeeCap = offer.continuousFeeCap;
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

    // Build a perfect tree from a non-empty power-of-two list. Duplicate hashes share nodes.
    function generateRoot(Offer[] memory leaves) public returns (bytes32) {
        require(leaves.length > 0 && (leaves.length & (leaves.length - 1)) == 0, "invalid leaves length");

        bytes32[] memory level = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            bytes32 leafHash = HashLib.hashOffer(leaves[i]);
            if (_isEmpty(tree[leafHash])) {
                newLeaf(leaves[i]);
            } else {
                require(isLeafNode(leafHash), "leaf id collision");
            }
            level[i] = leafHash;
        }

        while (level.length > 1) {
            uint256 nextLength = level.length / 2;
            bytes32[] memory next = new bytes32[](nextLength);

            for (uint256 i = 0; i < nextLength; i++) {
                bytes32 left = level[2 * i];
                bytes32 right = level[2 * i + 1];
                bytes32 nodeHash = HashLib.hashNode(left, right);
                Node storage n = tree[nodeHash];
                if (_isEmpty(n)) {
                    newInternalNode(nodeHash, left, right);
                } else {
                    require(
                        n.left == left && n.right == right && n.hashNode == nodeHash, "internal node id collision"
                    );
                }
                next[i] = nodeHash;
            }

            level = next;
        }

        return level[0];
    }

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

    function hashOffer(Offer memory offer) public pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function hashNode(bytes32 left, bytes32 right) public pure returns (bytes32) {
        return HashLib.hashNode(left, right);
    }

    function isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof)
        public
        pure
        returns (bool)
    {
        return HashLib.isLeaf(root, leafHash, leafIndex, proof);
    }

    function _hashLeaf(bytes32 id) public view returns (bytes32) {
        return _hashLeaf(tree[id].leaf);
    }

    // Reconstruct HashLib.hashOffer from the stored pre-image.
    function _hashLeaf(Leaf storage l) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                l.marketHash,
                l.buy,
                l.maker,
                l.start,
                l.expiry,
                l.tick,
                l.group,
                l.callback,
                l.callbackDataHash,
                l.receiverIfMakerIsSeller,
                l.ratifier,
                l.reduceOnly,
                l.maxUnits,
                l.maxAssets,
                l.continuousFeeCap
            )
        );
    }

    // A node is empty, a correctly hashed leaf, or a correctly hashed internal node with two children.
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (_isEmpty(n)) return true;
        if (n.left == 0 && n.right == 0) {
            bytes32 expected = _hashLeaf(n.leaf);
            return n.hashNode == expected && id == expected;
        }
        if (n.left != 0 && n.right != 0) {
            bytes32 leftHash = tree[n.left].hashNode;
            bytes32 rightHash = tree[n.right].hashNode;
            return leftHash != 0 && rightHash != 0 && n.hashNode == HashLib.hashNode(leftHash, rightHash);
        }
        return false;
    }

    // Check the path selected by leafIndex.
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
