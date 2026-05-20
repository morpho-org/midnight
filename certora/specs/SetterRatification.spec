// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using OfferTree as OfferTree;
using Utils as Utils;
using SetterRatifier as SetterRatifier;

methods {
    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.isWellFormed(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, uint256, bytes32[]) external returns (bytes32) envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.hashNode(bytes32, bytes32) external returns (bytes32) envfree;
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;

    function SetterRatifier.isRootRatified(address, bytes32) external returns (bool) envfree;

    // Align the merkle verification and the helper's well-formedness on the same hash functions.
    // Routing through Utils (`keccak256(abi.encode(...))`) lets Certora's bounded-hash recognition
    // supply injectivity automatically, instead of needing a ghost + axiom.
    function HashLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) => summaryHashOffer(offer);
    function HashLib.hashNode(bytes32 a, bytes32 b) internal returns (bytes32) => summaryHashNode(a, b);
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

function summaryHashNode(bytes32 a, bytes32 b) returns bytes32 {
    return Utils.hashNode(a, b);
}

// SetterRatifier-specific framing of takeCorrectness.
// Premise: the maker has explicitly committed to `root` via SetterRatifier.setIsRootRatified. Conclusion: every offer whose hash verifies against `root` via merkle proof is registered as a leaf in the maker's committed offer-tree.
rule setterRatifiedTakeCorrectness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    // Assume that the maker has explicitly committed to root via SetterRatifier.
    require SetterRatifier.isRootRatified(offer.maker, root);

    // Assume that root is the hash of node in the maker's tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // Assume that the tree is well-formed along the proof path from node down to a leaf.
    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute the leaf hash once so both uses below bind to the same symbolic value.
    bytes32 leafId = Utils.hashOffer(offer);

    require Utils.isLeaf(root, leafId, leafIndex, proof);

    assert OfferTree.isLeafNode(leafId);
}
