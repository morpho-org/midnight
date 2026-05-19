// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Rule B — Take correctness against the ghost offer-tree.
//
// Statement: if a maker-ratified root corresponds to a node `node` of a
// well-formed ghost offer-tree, and the supplied `(leafIndex, proof)` descends
// through well-formed nodes from `node`, then a successful merkle proof
// verification (`HashLib.isLeaf`) of `hashOffer(offer)` against that root
// implies the offer is registered as a leaf in the ghost tree (i.e. the offer
// was actually committed by the maker, not forged via second-preimage).
//
// The well-formed invariant on the ghost tree is established by Rule A
// (see OfferTreeWellFormed.spec).
//
// Architectural note (post-main merge): the merkle proof verification has
// moved out of `Midnight.take` and into the ratifier contracts
// (SetterRatifier / EcrecoverRatifier), which call `HashLib.isLeaf` after
// abi-decoding `(root, leafIndex, proof)` from `ratifierData`. The chain
// `successful take ⇒ successful isRatified` is established by
// Ratification.spec (takeRequiresMakerConsent); this rule covers the remaining
// link `successful isLeaf ⇒ leaf in tree`. Composed, the original
// take-level statement still holds.
//
// `HashLib.hashOffer` is summarized to `Utils.hashOffer`, which uses
// `keccak256(abi.encode(offer))`. This deviates from the contract's actual
// EIP-712 encoding but is sound for this rule because:
//   1. determinism is preserved across the merkle verification and the
//      helper-side leaf hash;
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
    function OfferTree.wellFormedPath(bytes32, uint256, bytes32[]) external envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;

    // Deterministic summary of HashLib.hashOffer so the merkle verification
    // (via Utils.isLeaf → HashLib.isLeaf → HashLib.hashNode) and the helper-side
    // leaf hash agree on the leaf-hash function. Unsummarized, the via-ir lowering
    // of the nested Offer.market.collateralParams[] loop blocks the prover's
    // pointer/memory analysis.
    function HashLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) =>
        summaryHashOffer(offer);

    // Deterministic + injective summary of HashLib.hashNode. The function uses
    // inline assembly which the prover treats as a black box without injectivity,
    // allowing CEXes where the upward fold (in `HashLib.isLeaf`) and the downward
    // walk (in `wellFormedPath`) produce the same root from structurally distinct
    // intermediate hashes. The ghost axiom below enforces ordered-pair injectivity,
    // matching keccak256's actual behavior on 64-byte inputs.
    function HashLib.hashNode(bytes32 a, bytes32 b) internal returns (bytes32) =>
        summaryHashNode(a, b);
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

persistent ghost ghostHashNode(bytes32, bytes32) returns bytes32 {
    // Injective on ordered pairs: equal hashes imply equal ordered inputs.
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        ghostHashNode(a1, b1) == ghostHashNode(a2, b2) => (a1 == a2 && b1 == b2);
}

function summaryHashNode(bytes32 a, bytes32 b) returns bytes32 {
    return ghostHashNode(a, b);
}

// ---------------------------------------------------------------------------
// Diagnostic rules — isolate whether Z3 can use the implication-form
// injectivity axiom on `ghostHashNode`. They do not exercise storage,
// `wellFormedPath`, or `hashOffer`; they only put `ghostHashNode` applications
// in front of the solver and ask it to derive the consequent of the axiom.
//
// If `diagInjectivityOneStep` fails: the axiom is unusable even at one level.
// If `diagInjectivityOneStep` passes but `diagInjectivityTwoStep` fails: the
// solver instantiates the axiom for ground arguments but does not chain
// through a compound `ghostHashNode(...)` sub-term — which is the chain
// structure `takeCorrectness` requires.
// ---------------------------------------------------------------------------

rule diagInjectivityOneStep(bytes32 a1, bytes32 b1, bytes32 a2, bytes32 b2) {
    require ghostHashNode(a1, b1) == ghostHashNode(a2, b2);
    assert a1 == a2;
    assert b1 == b2;
}

rule diagInjectivityTwoStep(bytes32 sib0, bytes32 sib1, bytes32 leaf1, bytes32 leaf2) {
    require ghostHashNode(ghostHashNode(sib0, leaf1), sib1)
         == ghostHashNode(ghostHashNode(sib0, leaf2), sib1);
    assert leaf1 == leaf2;
}

// Tests pure EUF substitution: combine an equation about a storage-derived
// `intermediate` with an equation about `ghostHashNode` applications, and ask
// Z3 to apply two-step injectivity through the substitution. If this passes,
// the SMT layer handles the substitution and the `takeCorrectness` bug must
// be in how `wellFormedPath` establishes its constraints (or in storage
// aliasing across the `wellFormedPath`/`Utils.isLeaf` boundary). If it fails,
// the axiom shape itself can't close this chain even when stated as plain
// SMT facts, and the axiom needs strengthening.
rule diagSubstitution(
    bytes32 root,
    bytes32 sib0,
    bytes32 sib1,
    bytes32 D,
    bytes32 leafHash,
    bytes32 intermediate
) {
    require ghostHashNode(intermediate, sib1) == root;
    require intermediate == ghostHashNode(sib0, D);
    require ghostHashNode(ghostHashNode(sib0, leafHash), sib1) == root;
    assert D == leafHash;
}

// Mirrors `takeCorrectness` but replaces the `hashOffer`-derived `leafId` with a
// free bytes32. If this passes: `hashOffer` (the offer-encoding side) is part
// of the problem. If it fails with the same shape: the failure lives entirely
// in the `wellFormedPath` + `Utils.isLeaf` composition through OfferTree
// storage, independent of how `leafHash` got there.
rule diagTakeCorrectnessFreeLeaf(bytes32 root, uint256 leafIndex, bytes32[] proof, bytes32 leafHash) {
    bytes32 node;
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);
    OfferTree.wellFormedPath(node, leafIndex, proof);
    require Utils.isLeaf(root, leafHash, leafIndex, proof);
    assert OfferTree.isLeafNode(leafHash);
}

/// Marquee rule: a successful merkle verification implies the offer's hash is a
/// leaf of the well-formed ghost tree pointed to by `root`.
rule takeCorrectness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;

    // Root is the hash of some node in the ghost tree.
    require OfferTree.getHash(node) == root;
    require root != to_bytes32(0);

    // The proof descends through well-formed nodes from that node.
    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute the offer's leaf hash once and reuse the symbolic value below.
    // Two syntactic `Utils.hashOffer(offer)` sites would each lower to
    // `keccak256(abi.encode(offer))` over freshly-materialized `bytes memory`;
    // the prover's hashing model only treats keccak as injective on
    // byte-equal inputs, and the `Offer.market.collateralParams[]` nested
    // dynamic array (the same pointer/memory analysis limitation that
    // motivates the `HashLib.hashOffer` summary above) blocks proving the
    // two encoded buffers identical. The merkle-fold side and the
    // assertion side could then bind to different symbolic hashes, yielding
    // a spurious CEX where the upward fold pins one hash to a leaf in the
    // ghost tree but the assertion reads a different hash that isn't.
    bytes32 leafId = Utils.hashOffer(offer);

    // Successful on-chain merkle verification: leafId folds up to root
    // along the supplied (leafIndex, proof).
    require Utils.isLeaf(root, leafId, leafIndex, proof);

    // The offer's hash is registered as a leaf in the ghost tree.
    assert OfferTree.isLeafNode(leafId);
}
