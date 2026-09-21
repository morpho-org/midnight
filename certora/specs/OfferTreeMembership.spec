// SPDX-License-Identifier: GPL-2.0-or-later

using GenerateRoot as generator;

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function hashOffer(OfferTree.Offer) external returns (bytes32) envfree;
    function generator.generateRoot(OfferTree.Offer[]) external returns (bytes32) envfree;
    function isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;
    function isLeafNode(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
    function wellFormedPath(bytes32, uint256, uint256) external returns (bool) envfree;
}

// Soundness: if a Merkle proof verifies along a well-formed path, hashOffer(offer) must be a leaf node.
rule membershipSoundness(OfferTree.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    require !isEmpty(root), "root is a populated node";
    require wellFormedPath(root, leafIndex, proof.length), "the path from the root to the leaf is well-formed";
    bytes32 leafId = hashOffer(offer);
    require isLeaf(root, leafId, leafIndex, proof), "Merkle proof verifies the offer";

    assert isLeafNode(leafId);
}

// The constructor leaves every model entry at its default value.
definition emptyNode(bytes32 id) returns bool = currentContract.tree[id].hash == to_bytes32(0) && currentContract.tree[id].left == to_bytes32(0) && currentContract.tree[id].right == to_bytes32(0) && currentContract.tree[id].leaf.marketHash == to_bytes32(0) && !currentContract.tree[id].leaf.buy && currentContract.tree[id].leaf.maker == 0 && currentContract.tree[id].leaf.start == 0 && currentContract.tree[id].leaf.expiry == 0 && currentContract.tree[id].leaf.tick == 0 && currentContract.tree[id].leaf.group == to_bytes32(0) && currentContract.tree[id].leaf.callback == 0 && currentContract.tree[id].leaf.callbackDataHash == to_bytes32(0) && currentContract.tree[id].leaf.receiverIfMakerIsSeller == 0 && currentContract.tree[id].leaf.ratifier == 0 && !currentContract.tree[id].leaf.reduceOnly && currentContract.tree[id].leaf.maxUnits == 0 && currentContract.tree[id].leaf.maxAssets == 0 && currentContract.tree[id].leaf.continuousFeeCap == 0;

// Check the generator itself, without assuming that its returned root or path is well-formed.
// This covers 1, 2, or 4 input offers and proofs of at most 4 siblings. Solidity loops (including
// collateral hashing) remain subject to loop_iter = 4 and the configured hash assumptions.
rule generatedRootMembershipSoundness(OfferTree.Offer[] offers, OfferTree.Offer offer, uint256 leafIndex, bytes32[] proof) {
    require offers.length == 1 || offers.length == 2 || offers.length == 4;
    require proof.length <= 4;
    require forall bytes32 id. emptyNode(id), "start from an empty model";

    bytes32 root = generator.generateRoot(offers);
    assert !isEmpty(root), "the generator returns a populated node";
    assert isWellFormed(root), "the generated root is well-formed";

    bytes32 leafId = hashOffer(offer);
    bool inFirst = leafId == hashOffer(offers[0]);
    bool inSecond = false;
    bool inSecondPair = false;
    if (offers.length >= 2) {
        inSecond = leafId == hashOffer(offers[1]);
    }
    if (offers.length == 4) {
        bytes32 third = hashOffer(offers[2]);
        bytes32 fourth = hashOffer(offers[3]);
        inSecondPair = leafId == third || leafId == fourth;
    }

    require isLeaf(root, leafId, leafIndex, proof), "Merkle proof verifies the offer";
    assert isLeafNode(leafId), "the verified hash is a leaf in the generated model";
    assert inFirst || inSecond || inSecondPair, "the verified offer hash belongs to the generator input";

    // Ensure the loop bounds and preconditions admit valid proofs for every supported input size.
    satisfy offers.length == 1;
    satisfy offers.length == 2;
    satisfy offers.length == 4;
}
