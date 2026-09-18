// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {GenerateRoot} from "../certora/helpers/GenerateRoot.sol";
import {OfferTree} from "../certora/helpers/OfferTree.sol";
import {Offer} from "../src/interfaces/IMidnight.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";

contract OfferTreeTest is Test {
    OfferTree internal tree;
    GenerateRoot internal rootReference;

    function setUp() public {
        tree = new OfferTree();
        rootReference = new GenerateRoot();
    }

    function testGenerateRootMatchesOfferTree(uint256 leftTick, uint256 rightTick) public {
        Offer memory leftOffer;
        leftOffer.tick = leftTick;
        Offer memory rightOffer;
        rightOffer.tick = rightTick;
        bytes32 left = HashLib.hashOffer(leftOffer);
        bytes32 right = HashLib.hashOffer(rightOffer);
        assertEq(tree.newLeaf(leftOffer), left);
        assertEq(tree.newLeaf(rightOffer), right);
        assertEq(tree.newLeaf(leftOffer), left);
        assertFalse(tree.isEmpty(left));
        assertTrue(tree.isLeafNode(left));
        assertTrue(tree.isWellFormed(left));

        bytes32 parent = tree.newInternalNode(left, right);
        assertEq(parent, keccak256(abi.encode(left, right)));
        assertEq(tree.newInternalNode(left, right), parent);
        assertFalse(tree.isEmpty(parent));
        assertTrue(tree.isWellFormed(parent));

        Offer[] memory offers = new Offer[](4);
        offers[0] = leftOffer;
        offers[1] = rightOffer;
        offers[2] = leftOffer;
        offers[3] = rightOffer;
        bytes32 root = rootReference.generateRoot(offers);
        assertEq(root, keccak256(abi.encode(parent, parent)));
        assertTrue(tree.isEmpty(root));
        assertEq(tree.newInternalNode(parent, parent), root);
        assertFalse(tree.isEmpty(root));
        assertTrue(tree.isWellFormed(root));

        bytes32[] memory proof = new bytes32[](2);
        proof[1] = parent;
        for (uint256 i = 0; i < offers.length; i++) {
            proof[0] = i % 2 == 0 ? right : left;
            assertTrue(HashLib.isLeaf(root, HashLib.hashOffer(offers[i]), i, proof));
        }
        assertEq(rootReference.generateRoot(offers), root);
    }

    function testGenerateRootWithDuplicateSiblings() public view {
        Offer[] memory offers = new Offer[](4);
        bytes32 leaf = HashLib.hashOffer(offers[0]);
        bytes32 parent = keccak256(abi.encode(leaf, leaf));
        bytes32 expectedRoot = keccak256(abi.encode(parent, parent));

        assertEq(rootReference.generateRoot(offers), expectedRoot);
        assertTrue(tree.isEmpty(leaf));
        assertTrue(tree.isEmpty(parent));
        assertTrue(tree.isEmpty(expectedRoot));
        assertEq(rootReference.generateRoot(offers), expectedRoot);
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
        assertFalse(tree.isEmpty(parent));
        assertTrue(tree.isWellFormed(parent));
    }
}
