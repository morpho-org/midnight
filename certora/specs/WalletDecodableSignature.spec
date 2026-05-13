// SPDX-License-Identifier: GPL-2.0-or-later

// Wallet decodable signature — soundness of the Midnight Offer-tree
// verifier under wallet-side EIP-712 signing.
//
// Critical claim
//   If `UtilsLib.isLeaf(rootHash, candidateOfferHash, proof)` accepts a
//   candidate against the root of a well-formed sort-labeled tree, then
//   `candidateOfferHash` is the hash of one of the offers the maker
//   actually signed (i.e. a leaf actually stored in the tree).
//
// Why this is the only safety-critical claim
//   The maker signs ONE typed-data blob covering a batch. If the verifier
//   accepts an unauthorized leaf hash, funds can be moved against an
//   offer the maker never approved — liquidation against unsigned terms,
//   collateral seized, real money loss. Liveness ("legitimate offers
//   are takeable") is desirable but its failure mode is benign — batch
//   gets re-signed. Hence the spec focuses on soundness.
//
// Proof structure
//   (A) `wellFormed` invariant — storage shape preserved by every
//       reachable state transition.
//   (B) `acceptedProofMatchesStoredLeaf` — soundness. Conditioning on the
//       chain reaching the stored root from a candidate via the proof,
//       keccak injectivity forces the candidate to equal the stored
//       offerHash at the corresponding leaf. Mirrors the pen-and-paper
//       Property 2: the smallest-index argument.
//
//   The helper packages the storage walk, expected-hash threading and
//   chain reconstruction into a single external view call so all hash
//   equalities live in one symbolic frame (Certora's keccak modeling
//   reliably unifies identical-content hashes within a frame).

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
    function acceptedCandidateMatchesStoredLeaf(bytes32, bytes32[], bytes32) external returns (bool) envfree;
    function sortedPairHashEquivalence(bytes32, bytes32) external returns (bool, bool) envfree;
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

// (B) Soundness. The modeled verifier accepts only stored leaves.
rule acceptedProofMatchesStoredLeaf(bytes32 rootId, bytes32[] proof, bytes32 candidateOfferHash) {
    assert acceptedCandidateMatchesStoredLeaf(rootId, proof, candidateOfferHash);
}

// (C) Model-vs-production faithfulness. The modeled hashing form
// `keccak256(abi.encode(a, b))` (used in (B) via tree storage and the
// downward expected-hash threading) equals production's
// `UtilsLib.commutativeHash(a, b)` whenever the pair is sorted ascending.
// Combined with (B), this lifts the soundness proof from the model to the
// actual on-chain verifier `UtilsLib.isLeaf`.
rule modeledHashEqualsProductionHash(bytes32 a, bytes32 b) {
    bool sorted;
    bool equal;
    sorted, equal = sortedPairHashEquivalence(a, b);
    assert sorted => equal;
}
