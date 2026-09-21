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
        bytes32 hash;
    }

    // Every populated node is keyed by its hash.
    mapping(bytes32 => Node) internal tree;

    // Create a leaf or return its existing hash ID.
    function newLeaf(Offer memory offer) public returns (bytes32 id) {
        id = HashLib.hashOffer(offer);
        require(id != 0, "id is the zero bytes");
        Node storage n = tree[id];
        if (!isEmpty(n)) return id;
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
        n.hash = id;
    }

    // Create an internal node or return its existing hash ID.
    function newInternalNode(bytes32 left, bytes32 right) public returns (bytes32 id) {
        bytes32 leftHash = tree[left].hash;
        bytes32 rightHash = tree[right].hash;
        require(leftHash != 0, "left empty");
        require(rightHash != 0, "right empty");
        id = HashLib.hashNode(leftHash, rightHash);
        require(id != 0, "zero hash");
        Node storage n = tree[id];
        if (!isEmpty(n)) return id;
        n.left = left;
        n.right = right;
        n.hash = id;
    }

    function isEmpty(Node storage n) internal view returns (bool) {
        return n.hash == 0;
    }

    function isEmpty(bytes32 id) public view returns (bool) {
        return isEmpty(tree[id]);
    }

    function isLeafNode(bytes32 id) public view returns (bool) {
        return tree[id].left == 0 && tree[id].right == 0 && tree[id].hash != 0;
    }

    function hashOffer(Offer memory offer) public pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof)
        public
        pure
        returns (bool)
    {
        return HashLib.isLeaf(root, leafHash, leafIndex, proof);
    }

    // Reconstruct HashLib.hashOffer from the stored pre-image.
    function hashLeaf(Leaf storage l) internal view returns (bytes32) {
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

    // Empty nodes are fully zeroed. Populated nodes have their hash as identifier and hash their leaf data or their
    // two non-empty children.
    function isWellFormed(bytes32 id) public view returns (bool) {
        Node storage n = tree[id];
        if (isEmpty(n)) {
            Leaf storage l = n.leaf;
            return n.left == 0 && n.right == 0 && l.marketHash == 0 && !l.buy && l.maker == address(0) && l.start == 0
                && l.expiry == 0 && l.tick == 0 && l.group == 0 && l.callback == address(0) && l.callbackDataHash == 0
                && l.receiverIfMakerIsSeller == address(0) && l.ratifier == address(0) && !l.reduceOnly
                && l.maxUnits == 0 && l.maxAssets == 0 && l.continuousFeeCap == 0;
        }
        if (n.left == 0 && n.right == 0) {
            bytes32 expected = hashLeaf(n.leaf);
            return n.hash == expected && id == expected;
        }
        if (n.left != 0 && n.right != 0) {
            bytes32 leftHash = tree[n.left].hash;
            bytes32 rightHash = tree[n.right].hash;
            return leftHash != 0 && rightHash != 0 && n.hash == id && n.hash == HashLib.hashNode(leftHash, rightHash);
        }
        return false;
    }

    // Check the path selected by leafIndex.
    function wellFormedPath(bytes32 id, uint256 leafIndex, uint256 depth) public view returns (bool) {
        for (uint256 i = depth;;) {
            require(isWellFormed(id));

            if (i == 0) break;

            --i;
            id = ((leafIndex >> i) & 1 == 0) ? tree[id].left : tree[id].right;
        }
        return true;
    }
}
