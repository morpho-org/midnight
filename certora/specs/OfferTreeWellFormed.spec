// SPDX-License-Identifier: GPL-2.0-or-later

// Leaves store the fixed-size pre-image of `hashOffer` (its scalar fields plus `marketHash` and `callbackDataHash`)
// instead of the raw `Offer`, so `isWellFormed` re-hashes a leaf with one bounded keccak (`_hashLeaf`) and the
// invariant scales. The rules below justify the trick: `newLeafConnectsHashLeafToHashOffer` checks `_hashLeaf`
// faithfully reproduces `hashOffer`, `leafHashDisjointFromNodeHash` checks leaf and internal hashes never collide,
// and `nodeHashInjective` underpins the merkle reasoning in OfferTreeMembership.spec.

methods {
    function newLeaf(OfferTree.Offer) external envfree;
    function _hashLeaf(bytes32) external returns (bytes32) envfree;
    function hashOffer(OfferTree.Offer) external returns (bytes32) envfree;
    function hashNode(bytes32, bytes32) external returns (bytes32) envfree;
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

// `_hashLeaf` reproduces the real `hashOffer` for the pre-image stored by `newLeaf`.
rule newLeafConnectsHashLeafToHashOffer(OfferTree.Offer offer) {
    bytes32 id = hashOffer(offer);

    require id != to_bytes32(0);
    require isEmpty(id);

    newLeaf(offer);

    assert _hashLeaf(id) == id;
    assert _hashLeaf(id) == hashOffer(offer);
}

// A recomputed leaf hash never equals an internal-node hash: image(_hashLeaf) and image(hashNode) are disjoint.
rule leafHashDisjointFromNodeHash(bytes32 id, bytes32 a, bytes32 b) {
    assert _hashLeaf(id) != hashNode(a, b);
}

// hashNode is injective, which the merkle peeling in OfferTreeMembership.spec relies on.
rule nodeHashInjective(bytes32 a, bytes32 b, bytes32 c, bytes32 d) {
    require hashNode(a, b) == hashNode(c, d);
    assert a == c && b == d;
}
