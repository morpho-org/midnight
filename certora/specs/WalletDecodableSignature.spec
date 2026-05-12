// SPDX-License-Identifier: GPL-2.0-or-later

// Wallet decodable signature: end-to-end correctness for the Midnight
// Offer tree under wallet-side EIP-712 signing.
//
// Claim
//   If a tree built via OfferTree's `newLeaf` + `newInternalNode` is
//   well-formed, every leaf is takeable on-chain via `UtilsLib.isLeaf`.
//
//   Well-formed = at every internal node: two non-empty children with
//   `L.hash <= R.hash` and `hashNode == keccak256(abi.encode(L, R))`.
//
// Proof structure
//   (A) `wellFormed` invariant — storage shape preserved by every
//       reachable state transition.
//   (B) `verifierAcceptsSortedTree` — forward direction at the chain
//       level: sort-labeled construction at every level yields a root
//       the real `UtilsLib.isLeaf` accepts for any leaf and any proof.
//   (C) `verifierRejectsSpoofedLeaves` — storage-tied non-spoofability
//       (URD `claimCorrectness` pattern): any candidate leaf hash that
//       passes the chain verifier against a well-formed tree's stored
//       root must equal the offerHash actually stored at the
//       corresponding tree leaf.
//
// Bridge (construction-level identity, not machine-checked):
//   Wallet's EIP-712 array hash of a sort-labeled tree coincides with
//   `keccak256(abi.encode(L, R))` at every level by construction of
//   `newInternalNode`. So (B)'s wallet root equals (A)'s stored root.

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
    function getHash(bytes32) external returns (bytes32) envfree;
    function getOfferHash(bytes32) external returns (bytes32) envfree;
    function wellFormedPathToLeaf(bytes32, bytes32[]) external returns (bytes32) envfree;
    function verifierAcceptsSortLabeledRoot(bytes32, bytes32[]) external returns (bool) envfree;
    function requireChainReaches(bytes32, bytes32, bytes32[]) external envfree;
    function chainReaches(bytes32, bytes32, bytes32[]) external returns (bool) envfree;
}

// (A) Storage shape invariants.
strong invariant zeroIsEmpty()
    isEmpty(to_bytes32(0));

strong invariant wellFormed(bytes32 id)
    isWellFormed(id)
    {
        preserved {
            requireInvariant zeroIsEmpty();
        }
    }

// (B1) Forward direction at the chain level. Sort-labeled construction
// yields a root the production `UtilsLib.isLeaf` accepts. Same single
// frame, both sides reduce to `keccak(min, max)` per level — provable
// by Certora's intra-frame keccak determinism. Mostly serves as a
// regression check on the helper's correspondence to production.
rule verifierAcceptsSortedTree(bytes32 leafHash, bytes32[] proof) {
    assert verifierAcceptsSortLabeledRoot(leafHash, proof);
}

// (B2) Forward direction storage-tied. For any leaf reachable via a
// well-formed path from `rootId`, the chain verifier accepts the leaf's
// stored offerHash with that proof against the tree's stored root.
// Relies on cross-frame keccak unification: the `keccak(bytes.concat(...))`
// leaf wrap and `keccak(abi.encode(L, R))` internal hashing forms are
// identical on both the storage side (`newLeaf`, `newInternalNode`) and
// the chain side (`chainReaches`), so the prover can match terms.
rule verifierAcceptsStoredLeaves(bytes32 rootId, bytes32[] proof) {
    bytes32 leafId = wellFormedPathToLeaf(rootId, proof);
    bytes32 leafOfferHash = getOfferHash(leafId);
    bytes32 rootHash = getHash(rootId);
    // Exclude the trivially-vacuous empty-tree case where every storage
    // value is zero and the walk lands at an unpopulated node.
    require leafOfferHash != to_bytes32(0);
    assert chainReaches(rootHash, leafOfferHash, proof);
}

// (C) Non-spoofability. Conditioning on the chain verifier accepting a
// candidate offer hash against the tree's stored root, keccak
// injectivity (across the URD-style leaf wrap and internal-node hashing)
// forces the candidate to equal the actually-stored offerHash at the
// walked-to leaf.
rule verifierRejectsSpoofedLeaves(bytes32 rootId, bytes32[] proof, bytes32 candidateOfferHash) {
    bytes32 leafId = wellFormedPathToLeaf(rootId, proof);
    bytes32 rootHash = getHash(rootId);
    requireChainReaches(rootHash, candidateOfferHash, proof);
    bytes32 storedOfferHash = getOfferHash(leafId);
    assert candidateOfferHash == storedOfferHash;
}
