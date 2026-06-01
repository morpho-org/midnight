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

// The main correctness result of the verification.
// It ensures that if the root is setup according to a well-formed offer tree, then a successful Merkle verification of an offer against that root implies the offer is registered as a leaf in the tree.
rule membershipSoundness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    // Assume that root is the hash of node in the tree.
    require OfferTree.getHash(node) == root;

    // Assume that the root is non-zero, otherwise empty nodes would hash-match it.
    require root != to_bytes32(0);

    // No need to make sure that node is equal to the root: one can pass an internal node instead.
    // Assume that the tree is well-formed along the path down to the leaf.
    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute the leaf identifier once so both uses below bind to the same hash.
    bytes32 leafId = Utils.hashOffer(offer);

    // Assume that the leaf identifier is non-zero, matching the constraint enforced by newLeaf.
    require leafId != to_bytes32(0);

    // Assume that the Merkle proof verifies the offer's hash against the root.
    require Utils.isLeaf(root, leafId, leafIndex, proof);

    assert OfferTree.isLeafNode(leafId);
}
