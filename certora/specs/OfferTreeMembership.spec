// SPDX-License-Identifier: GPL-2.0-or-later

using OfferTree as OfferTree;
using Utils as Utils;

methods {
    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, uint256, bytes32[]) external returns (bool) envfree;
    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;
}

// Headline Correctness Rule:
// If the root is setup according to a well-formed offer tree, then a successful Merkle verification of an offer against that root implies the offer is registered as a leaf in the tree.
rule membershipSoundness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    require OfferTree.getHash(node) == root, "root is the hash of node";

    require(OfferTree.wellFormedPath(node, leafIndex, proof), "the path from the root to the leaf is well-formed");

    bytes32 leafId = Utils.hashOffer(offer);

    require Utils.isLeaf(root, leafId, leafIndex, proof), "Merkle proof verifies the offer";

    assert OfferTree.isLeafNode(leafId);
}
