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
//
// `UtilsLib.hashOffer` is summarized to `Utils.hashOffer`, which uses
// `keccak256(abi.encode(offer))`. This deviates from the contract's actual
// EIP-712 encoding but is sound for this rule because:
//   1. determinism is preserved across the contract call inside `take` and
//      the helper-side leaf hash;
//   2. injectivity assumed via `optimistic_hashing`;
//   3. the rule reasons about the hash purely as an opaque commitment —
//      its specific bit pattern doesn't matter, only that it is the same
//      function on both sides.

using OfferTree as OfferTree;
using Utils as Utils;

methods {
    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.isWellFormed(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, bytes32[]) external envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;

    // Deterministic summary of UtilsLib.hashOffer so the contract and the spec
    // agree on the leaf-hash function. Unsummarized, the via-ir lowering of the
    // nested Offer.obligation.collateralParams[] loop blocks the prover's
    // pointer/memory analysis.
    function UtilsLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) =>
        summaryHashOffer(offer);

    // Deterministic + symmetric + injective summary of UtilsLib.commutativeHash.
    // The function uses inline assembly which the prover treats as a black box
    // without injectivity, allowing CEXes where the upward fold (in `take`)
    // and the downward walk (in `wellFormedPath`) produce the same root from
    // structurally distinct intermediate hashes. The ghost axioms below enforce
    // sorted-pair determinism and injectivity, matching keccak256's actual
    // behavior on 64-byte inputs.
    function UtilsLib.commutativeHash(bytes32 a, bytes32 b) internal returns (bytes32) =>
        summaryCommutativeHash(a, b);

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
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

persistent ghost ghostCommutativeHash(bytes32, bytes32) returns bytes32 {
    // Symmetric in its arguments.
    axiom forall bytes32 a. forall bytes32 b.
        ghostCommutativeHash(a, b) == ghostCommutativeHash(b, a);
    // Injective on unordered pairs: equal hashes imply equal unordered inputs.
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        ghostCommutativeHash(a1, b1) == ghostCommutativeHash(a2, b2)
            => ((a1 == a2 && b1 == b2) || (a1 == b2 && b1 == a2));
}

function summaryCommutativeHash(bytes32 a, bytes32 b) returns bytes32 {
    return ghostCommutativeHash(a, b);
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
    bytes32 leafId = Utils.hashOffer(offer);
    assert OfferTree.isLeafNode(leafId);
    assert OfferTree.getHash(leafId) == leafId;
}
