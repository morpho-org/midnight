// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib, OFFER_TYPEHASH} from "../../src/ratifiers/libraries/HashLib.sol";

// A leaf's offer reaches HashLib.hashOffer only through fixed-size fields: every dynamic member of Offer
// (market.collateralParams and callbackData) is already reduced to a single bytes32 before the final
// keccak (hashMarket(market) and keccak256(callbackData)). So we store that fixed-size pre-image instead
// of the raw Offer. This keeps every Node fixed-size, so isWellFormed re-hashes a leaf with one bounded
// keccak (no dynamic-array reads, no loops) — the property that lets the wellFormed invariant scale, exactly
// as it does for URD's fixed-size leaves. _hashLeaf mirrors hashOffer's outer keccak field-for-field, so a
// leaf's id is the real hashOffer value; the wellFormed invariant's newLeaf case checks this mirror holds
// (id == hashOffer(offer) and id == _hashLeaf(leaf)), so the correspondence is verified, not assumed.
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
        // hash of the offer for leaves, and of [left.hash, right.hash] for internal nodes.
        bytes32 hashNode;
    }

    /* STORAGE */

    // The tree has no root because every node (and the nodes underneath) form an offer tree.
    // We use bytes32 as keys of the mapping so that leaves have an identifier that is the hash of the offer.
    // Identical offers therefore share a single node (referenced by multiple parents).
    // For internal nodes the key is left arbitrary, so that the certificate generation can choose freely any bytes32
    // value (that is not already used).
    // Leaves keep the fixed-size pre-image of hashOffer (see Leaf) so isWellFormed can recompute a leaf's hash
    // and pin its hashNode into the image of hashOffer. hashOffer and hashNode feed keccak distinct
    // input shapes, this gives domain separation between leaves and internal nodes. The tree is built only via newLeaf
    // and newInternalNode (directly or through generateRoot), which preserve well-formedness by construction.
    mapping(bytes32 => Node) internal tree;

    /* MAIN FUNCTIONS */

    function newLeaf(Offer memory offer) public {
        bytes32 id = HashLib.hashOffer(offer);
        require(id != 0, "id is the zero bytes");
        Node storage n = tree[id];
        require(_isEmpty(n), "leaf is not empty");
        // Store the fixed-size pre-image of hashOffer; the dynamic members are kept only as their sub-hashes.
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

    // Build a perfect binary tree from a non-empty, power-of-two list of offers and return its root.
    // Duplicate leaves and subtrees share the same node because their identifiers are their hashes.
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

    // Recompute the leaf hash from its stored fixed-size pre-image. Mirrors HashLib.hashOffer's outer keccak
    // field-for-field, with marketHash standing in for hashMarket(market) and callbackDataHash for
    // keccak256(callbackData). Equals HashLib.hashOffer(offer) whenever the fields were extracted from offer.
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

    // The specification of a well-formed tree is the following:
    //   - empty nodes are well-formed
    //   - leaves have the correct identifier and hashing
    //   - internal nodes have the correct hashing
    //   - internal nodes have exactly two non-empty children
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

    // Check that the nodes are well-formed starting from id and going down the tree.
    // The bits of leafIndex choose the path downward; the depth is proof.length.
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
