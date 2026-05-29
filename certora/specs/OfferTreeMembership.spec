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

/// SOUNDNESS ///

/// If a root corresponds to a node of a well-formed offer-tree, a successful merkle verification of the offer's hash against that root implies the offer is registered as a leaf in the tree.
rule membershipSoundness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;
    require OfferTree.getHash(node) == root, "root is the hash of node";
    require root != to_bytes32(0), "root is non-zero";

    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute leafId once so both uses below bind to the same symbolic hash.
    bytes32 leafId = Utils.hashOffer(offer);
    require leafId != to_bytes32(0), "leafId is non-zero";
    require Utils.isLeaf(root, leafId, leafIndex, proof), "merkle proof verifies";

    assert OfferTree.isLeafNode(leafId);
}
