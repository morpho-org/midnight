// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using OfferTree as OfferTree;
using Utils as Utils;

methods {
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.isWellFormed(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, uint256, bytes32[]) external returns (bytes32) envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;

    // Summarized so the merkle verification and the helper-side leaf hash agree on the leaf-hash function.
    function HashLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) => summaryHashOffer(offer);

    // Summarized to a ghost so the upward fold and the downward walk see the same injective hash function.
    function HashLib.hashNode(bytes32 a, bytes32 b) internal returns (bytes32) => summaryHashNode(a, b);

    // Take-side externals summarized as NONDET / havoc — irrelevant to the merkle-membership property.
    // `isRatified` is NONDET'd so the rule abstracts over the ratifier choice: the bridge from
    // `take ⇒ Utils.isLeaf success` is supplied explicitly in `takeImpliesLeafInTree` below.
    function _.isRatified(Midnight.Offer, bytes) external => NONDET;
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function IdLib.toId(Midnight.Market memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

// Injective on ordered pairs.
persistent ghost ghostHashNode(bytes32, bytes32) returns bytes32 {
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2. ghostHashNode(a1, b1) == ghostHashNode(a2, b2) => (a1 == a2 && b1 == b2);
}

function summaryHashNode(bytes32 a, bytes32 b) returns bytes32 {
    return ghostHashNode(a, b);
}

// The main correctness result of the verification.
// If a maker-ratified root corresponds to a node of a well-formed offer-tree, then a successful merkle verification of the offer's hash against that root implies the offer is registered as a leaf in the tree.
rule takeCorrectness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    // Assume that root is the hash of node in the tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // Assume that the tree is well-formed along the proof path from node down to a leaf.
    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute the leaf hash once so both uses below bind to the same symbolic value.
    bytes32 leafId = Utils.hashOffer(offer);

    require Utils.isLeaf(root, leafId, leafIndex, proof);

    assert OfferTree.isLeafNode(leafId);
}

// The completeness dual of takeCorrectness.
// Every leaf in a well-formed offer-tree has a verifying merkle proof: folding the path's sibling hashes back up against the leaf reproduces the root.
rule takeCompleteness(bytes32 node, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    // Assume that root is the hash of node in the tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // Walk the well-formed path; the call returns the leaf at the bottom.
    bytes32 endLeaf = OfferTree.wellFormedPath(node, leafIndex, proof);

    assert Utils.isLeaf(root, endLeaf, leafIndex, proof);
}

// The take-level guarantee: every successful Midnight.take is for an offer registered as a leaf in the maker's offer-tree.
// The bridge from take's success to the merkle check is supplied by `require Utils.isLeaf(...)` below. It is justified by composition: take's body requires `isRatified(offer, ratifierData) == CALLBACK_SUCCESS`, and both SetterRatifier and EcrecoverRatifier implementations `require(HashLib.isLeaf(root, hashOffer(offer), leafIndex, proof))` for the (root, leafIndex, proof) they decode from ratifierData — regardless of how the maker committed the root (on-chain via `isRootRatified`, or off-chain via EIP-712 signature).
rule takeImpliesLeafInTree(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    // Assume that root is the hash of node in the maker's tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // Assume that the tree is well-formed along the proof path from node down to a leaf.
    OfferTree.wellFormedPath(node, leafIndex, proof);

    bytes32 leafId = Utils.hashOffer(offer);

    // Bridge: a successful take implies the chosen ratifier's `isRatified` returned CALLBACK_SUCCESS, which implies `HashLib.isLeaf(...)` passed for the (root, leafIndex, proof) it decoded from ratifierData. We model that decoded triple as the rule's (root, leafIndex, proof).
    require Utils.isLeaf(root, leafId, leafIndex, proof);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);

    assert OfferTree.isLeafNode(leafId);
}
