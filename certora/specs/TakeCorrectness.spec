// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Rule B — Take correctness against the ghost offer-tree.
//
// Statement: if the maker's signed root corresponds to a node `node` of a
// well-formed ghost offer-tree, and the supplied proof descends through
// well-formed nodes from `node`, then any successful `take` against
// `(offer, root, proof)` implies `hashOffer(offer)` is registered as a
// leaf in the ghost tree (i.e. the offer was actually committed by the
// maker, not forged via second-preimage).
//
// The well-formed invariant on the ghost tree is established by Rule A
// (see OfferTreeWellFormed.spec).

using OfferTree as OfferTree;

methods {
    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.isWellFormed(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, bytes32[]) external envfree;
    function OfferTree.hashOffer(Midnight.Offer) external returns (bytes32) envfree;

    // Real semantics required for hashOffer / isLeaf / commutativeHash:
    // these are the functions whose interaction with the ghost tree we are
    // verifying. Do NOT summarize.

    // Summarize internals irrelevant to the merkle/hash linkage.
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
}

/// Marquee rule: a successful take implies the offer's hash is a leaf of the
/// well-formed ghost tree pointed to by `root`.
rule takeCorrectness(
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    bytes32 node;

    // Root is the hash of some node in the ghost tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // The proof descends through well-formed nodes from that node.
    OfferTree.wellFormedPath(node, proof);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    // The offer's hash is registered as a leaf in the ghost tree.
    bytes32 leafId = OfferTree.hashOffer(offer);
    assert OfferTree.isLeafNode(leafId);
    assert OfferTree.getHash(leafId) == leafId;
}
