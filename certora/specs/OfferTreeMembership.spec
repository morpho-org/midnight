// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function hashOffer(OfferTree.Offer) external returns (bytes32) envfree;
    function isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;
    function isLeafNode(bytes32) external returns (bool) envfree;
    function wellFormedPath(bytes32, uint256, uint256) external returns (bool) envfree;
}

// Soundness: if a Merkle proof verifies along a well-formed path, hashOffer(offer) must be a leaf node.
rule membershipSoundness(OfferTree.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    require !isEmpty(root), "root is a populated node";
    require wellFormedPath(root, leafIndex, proof.length), "the path from the root to the leaf is well-formed";
    bytes32 leafId = hashOffer(offer);
    require isLeaf(root, leafId, leafIndex, proof), "Merkle proof verifies the offer";

    assert isLeafNode(leafId);
}
