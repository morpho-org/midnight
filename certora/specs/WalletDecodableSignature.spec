// SPDX-License-Identifier: GPL-2.0-or-later

// Wallet decodable signature: end-to-end correctness for the Midnight
// Offer tree under wallet-side EIP-712 signing.
//
// Claim
//   If a tree built via OfferTree's `newLeaf` + `newInternalNode` is
//   well-formed, every leaf is takeable on-chain via `UtilsLib.isLeaf`.
//
//   Well-formed = at every internal node: two non-empty children with
//   `L.hash <= R.hash`, `offerHash == 0`, and
//   `hashNode == keccak256(abi.encode(L, R))`.
//
// Proof structure
//   (A) `wellFormed` invariant — storage shape preserved by every
//       reachable state transition.
//   (B) `verifierAcceptsSortedTree` — forward direction at the chain
//       level: sort-labeled construction at every level yields a root
//       the real `UtilsLib.isLeaf` accepts for any leaf and any proof.
//   (C) `verifierAcceptsStoredLeaves` and
//       `acceptedProofMatchesStoredLeaf` — storage-tied forward
//       correctness and soundness, using URD-style single-frame helpers.
//       The tree walk, leaf lookup, and hash folding are deliberately
//       packaged into one Solidity helper call because Certora's hash
//       model is much more effective when all equalities appear in the
//       same symbolic frame than when they are split across several
//       external calls.
//
// Bridge (construction-level identity, not machine-checked):
//   Wallet's EIP-712 array hash of a sort-labeled tree coincides with
//   `keccak256(abi.encode(L, R))` at every level by construction of
//   `newInternalNode`. So (B)'s wallet root equals (A)'s stored root.

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
    function verifierAcceptsSortLabeledRoot(bytes32, bytes32[]) external returns (bool) envfree;
    function storedLeafReachesRoot(bytes32, bytes32[]) external returns (bool) envfree;
    function acceptedCandidateMatchesStoredLeaf(bytes32, bytes32[], bytes32) external returns (bool) envfree;
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
// well-formed path from `rootId`, the chain verifier accepts the stored
// leaf reached by that proof against the stored root. This rule is
// written against a single-frame helper on purpose: in practice, Certora
// often loses the crucial hash equalities when storage walk, leaf read,
// and chain reconstruction are asserted via separate helper calls. The
// helper therefore threads the expected hash downward from the root,
// instead of recomputing the same chain from leaf to root in a second
// pass.
rule verifierAcceptsStoredLeaves(bytes32 rootId, bytes32[] proof) {
    assert storedLeafReachesRoot(rootId, proof);
}

// (C) Direct soundness rule from the pen-and-paper proof. Fix a
// well-formed stored tree and a proof. If the commutative-hash verifier
// reaches the stored root from some candidate offer hash using that
// proof, then the candidate must equal the stored offerHash at the leaf
// reached by the same proof. Again, the helper keeps the whole argument
// in one frame and threads the expected hash downward to avoid cross-call
// loss of hash equalities.
rule acceptedProofMatchesStoredLeaf(bytes32 rootId, bytes32[] proof, bytes32 candidateOfferHash) {
    assert acceptedCandidateMatchesStoredLeaf(rootId, proof, candidateOfferHash);
}
