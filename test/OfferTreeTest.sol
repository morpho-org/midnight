// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {GenerateRoot} from "../certora/helpers/GenerateRoot.sol";
import {Offer} from "../src/interfaces/IMidnight.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";

contract OfferTreeTest is Test {
    GenerateRoot internal tree;

    function setUp() public {
        tree = new GenerateRoot();
    }

    function testGenerateRootWithPrebuiltSubtree(uint256 leftTick, uint256 rightTick) public {
        Offer memory leftOffer;
        leftOffer.tick = leftTick;
        Offer memory rightOffer;
        rightOffer.tick = rightTick;
        bytes32 left = HashLib.hashOffer(leftOffer);
        bytes32 right = HashLib.hashOffer(rightOffer);
        assertEq(tree.newLeaf(leftOffer), left);
        assertEq(tree.newLeaf(rightOffer), right);
        assertEq(tree.newLeaf(leftOffer), left);
        assertEq(tree.getHash(left), left);
        assertTrue(tree.isLeafNode(left));
        assertTrue(tree.isWellFormed(left));

        bytes32 parent = tree.newInternalNode(left, right);
        assertEq(parent, keccak256(abi.encode(left, right)));
        assertEq(tree.newInternalNode(left, right), parent);
        assertEq(tree.getHash(parent), parent);
        assertTrue(tree.isWellFormed(parent));

        Offer[] memory offers = new Offer[](4);
        offers[0] = leftOffer;
        offers[1] = rightOffer;
        offers[2] = leftOffer;
        offers[3] = rightOffer;
        bytes32 root = tree.generateRoot(offers);
        assertEq(root, keccak256(abi.encode(parent, parent)));
        assertEq(tree.getHash(root), root);
        assertTrue(tree.isWellFormed(root));

        bytes32[] memory proof = new bytes32[](2);
        proof[1] = parent;
        for (uint256 i = 0; i < offers.length; i++) {
            proof[0] = i % 2 == 0 ? right : left;
            assertTrue(HashLib.isLeaf(root, HashLib.hashOffer(offers[i]), i, proof));
        }
        assertEq(tree.generateRoot(offers), root);
    }

    function testGenerateRootWithDuplicateSiblings() public {
        Offer[] memory offers = new Offer[](4);
        bytes32 leaf = HashLib.hashOffer(offers[0]);
        bytes32 parent = keccak256(abi.encode(leaf, leaf));
        bytes32 expectedRoot = keccak256(abi.encode(parent, parent));

        assertEq(tree.generateRoot(offers), expectedRoot);
        assertEq(tree.getHash(parent), parent);
        assertEq(tree.getHash(expectedRoot), expectedRoot);
        assertTrue(tree.isWellFormed(parent));
        assertTrue(tree.isWellFormed(expectedRoot));
        assertEq(tree.generateRoot(offers), expectedRoot);
    }

    function testNewInternalNodeRequiresPopulatedChildren() public {
        Offer memory offer;
        bytes32 leaf = HashLib.hashOffer(offer);
        tree.newLeaf(offer);

        vm.expectRevert("left empty");
        tree.newInternalNode(bytes32(0), leaf);
        vm.expectRevert("right empty");
        tree.newInternalNode(leaf, bytes32(0));

        bytes32 parent = tree.newInternalNode(leaf, leaf);
        assertEq(tree.getHash(parent), parent);
    }
}
