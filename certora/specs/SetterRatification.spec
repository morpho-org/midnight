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
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;

    function SetterRatifier.isRootRatified(address, bytes32) external returns (bool) envfree;

    // Summarized so the merkle verification and the helper-side leaf hash agree on the leaf-hash function.
    function HashLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) =>
        summaryHashOffer(offer);

    // Summarized to a ghost so the upward fold and the downward walk see the same injective hash function.
    function HashLib.hashNode(bytes32 a, bytes32 b) internal returns (bytes32) =>
        summaryHashNode(a, b);
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

// Injective on ordered pairs.
persistent ghost ghostHashNode(bytes32, bytes32) returns bytes32 {
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        ghostHashNode(a1, b1) == ghostHashNode(a2, b2) => (a1 == a2 && b1 == b2);
}

function summaryHashNode(bytes32 a, bytes32 b) returns bytes32 {
    return ghostHashNode(a, b);
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
