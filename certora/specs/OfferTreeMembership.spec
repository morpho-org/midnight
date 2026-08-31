// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function getHash(bytes32) external returns (bytes32) envfree;
    function hashOffer(OfferTree.Offer) external returns (bytes32) envfree;
    function isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;
    function isLeafNode(bytes32) external returns (bool) envfree;
    function wellFormedPath(bytes32, uint256, bytes32[]) external returns (bool) envfree;
}

// A valid proof in a well-formed tree identifies a registered leaf.
rule membershipSoundness(OfferTree.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;
    require getHash(node) == root, "root is the hash of node";
    require wellFormedPath(node, leafIndex, proof), "the path from the root to the leaf is well-formed";
    bytes32 leafId = hashOffer(offer);
    require isLeaf(root, leafId, leafIndex, proof), "Merkle proof verifies the offer";

    assert isLeafNode(leafId);
}
