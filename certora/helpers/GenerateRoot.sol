// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {OfferTree} from "./OfferTree.sol";
import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";

contract GenerateRoot is OfferTree {
    // Build a perfect tree from a non-empty power-of-two list. Duplicate hashes share nodes.
    function generateRoot(Offer[] memory leaves) public returns (bytes32) {
        require(leaves.length > 0 && (leaves.length & (leaves.length - 1)) == 0, "invalid leaves length");

        bytes32[] memory level = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            bytes32 leafHash = HashLib.hashOffer(leaves[i]);
            if (isEmpty(tree[leafHash])) {
                newLeaf(leaves[i]);
            } else {
                require(isLeafNode(leafHash), "leaf id collision");
            }
            level[i] = leafHash;
        }

        uint256 levelLength = level.length;
        while (levelLength > 1) {
            levelLength /= 2;
            for (uint256 i = 0; i < levelLength; i++) {
                bytes32 left = level[2 * i];
                bytes32 right = level[2 * i + 1];
                bytes32 nodeHash = HashLib.hashNode(left, right);
                Node storage n = tree[nodeHash];
                if (isEmpty(n)) {
                    newInternalNode(nodeHash, left, right);
                } else {
                    require(n.left == left && n.right == right && n.hash == nodeHash, "internal node id collision");
                }
                level[i] = nodeHash;
            }
        }

        return level[0];
    }
}
