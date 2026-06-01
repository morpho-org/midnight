// SPDX-License-Identifier: GPL-2.0-or-later

// No hashing summaries are needed: `Node` stores only the fixed-size pre-image of `hashOffer` (see OfferTree.sol),
// so `isWellFormed` re-hashes a leaf with a single bounded keccak over fixed-size storage — no dynamic-array reads,
// no loops. The only dynamic hashing is `newLeaf` hashing its offer argument once, which is cheap.

methods {
    function newLeaf(OfferTree.Offer) external envfree;
    function _hashLeaf(bytes32) external returns (bytes32) envfree;
    function hashOffer(OfferTree.Offer) external returns (bytes32) envfree;
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
}

// The zero node is empty, so it can serve as the canonical empty child of every node in the tree.
strong invariant zeroIsEmpty()
    isEmpty(to_bytes32(0));

// Every node of the tree is well-formed, which is what makes the membership result in OfferTreeMembership.spec sound.
strong invariant wellFormed(bytes32 id)
    isWellFormed(id)
    {
        preserved {
            requireInvariant zeroIsEmpty();
        }
    }

// Focused bridge check: `newLeaf` keys the node by `HashLib.hashOffer(offer)` and stores the fixed-size
// pre-image that `_hashLeaf` re-hashes. This rule catches drift between `_hashLeaf` and the real offer hash
// construction.
rule newLeafConnectsHashLeafToHashOffer(OfferTree.Offer offer) {
    bytes32 id = hashOffer(offer);

    require id != to_bytes32(0);
    require isEmpty(id);

    newLeaf(offer);

    assert _hashLeaf(id) == id;
    assert _hashLeaf(id) == hashOffer(offer);
}
