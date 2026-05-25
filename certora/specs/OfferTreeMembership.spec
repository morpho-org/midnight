// SPDX-License-Identifier: GPL-2.0-or-later

using OfferTree as OfferTree;
using Utils as Utils;

methods {
    function isAuthorized(address, address) external returns (bool) envfree;

    function OfferTree.getHash(bytes32) external returns (bytes32) envfree;
    function OfferTree.isLeafNode(bytes32) external returns (bool) envfree;
    function OfferTree.isWellFormed(bytes32) external returns (bool) envfree;
    function OfferTree.wellFormedPath(bytes32, uint256, bytes32[]) external returns (bool) envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.hashNode(bytes32, bytes32) external returns (bytes32) envfree;
    function Utils.isLeaf(bytes32, bytes32, uint256, bytes32[]) external returns (bool) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Align the merkle verification and the helper's well-formedness on the same hash functions.
    function HashLib.hashOffer(Midnight.Offer memory offer) internal returns (bytes32) => summaryHashOffer(offer);
    function HashLib.hashNode(bytes32 a, bytes32 b) internal returns (bytes32) => summaryHashNode(a, b);

    // A successful ratifier must witness a merkle proof for the offer's hash. The
    // obligation is discharged in Ratification.spec/isRatifiedRequiresIsLeaf, which
    // dispatches across all linked ratifier implementations.
    function _.isRatified(Midnight.Offer offer, bytes) external => isRatifiedSummary(offer) expect bytes32;
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
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

function summaryHashNode(bytes32 a, bytes32 b) returns bytes32 {
    return Utils.hashNode(a, b);
}

function isRatifiedSummary(Midnight.Offer offer) returns bytes32 {
    bytes32 result;
    bytes32 root;
    uint256 leafIndex;
    bytes32[] proof;
    require result == Utils.callbackSuccess() => Utils.isLeaf(root, Utils.hashOffer(offer), leafIndex, proof);
    return result;
}

/// SOUNDNESS ///

/// If a root corresponds to a node of a well-formed offer-tree, a successful merkle verification of the offer's hash against that root implies the offer is registered as a leaf in the tree.
rule takeCorrectness(Midnight.Offer offer, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;
    require OfferTree.getHash(node) == root, "root is the hash of node";
    require root != to_bytes32(0), "root is non-zero";

    OfferTree.wellFormedPath(node, leafIndex, proof);

    // Compute leafId once so both uses below bind to the same symbolic hash.
    bytes32 leafId = Utils.hashOffer(offer);
    require leafId != to_bytes32(0), "leafId is non-zero";
    require Utils.isLeaf(root, leafId, leafIndex, proof), "merkle proof verifies";

    assert OfferTree.isLeafNode(leafId);
}

/// TAKE-LEVEL LIFT ///

/// Every successful Midnight.take is for an offer registered as a leaf in the maker's offer-tree.
/// `require Utils.isLeaf(...)` binds the merkle witness to the specific (root, leafIndex, proof) used in the well-formedness premise; the take->ratifier->merkle composition is mechanised via the `isRatifiedSummary` above (obligation discharged in Ratification.spec/isRatifiedRequiresIsLeaf).
rule takeImpliesLeafInTree(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, uint256 leafIndex, bytes32[] proof) {
    bytes32 node;
    require OfferTree.getHash(node) == root, "root is the hash of node";
    require root != to_bytes32(0), "root is non-zero";

    OfferTree.wellFormedPath(node, leafIndex, proof);

    bytes32 leafId = Utils.hashOffer(offer);
    require Utils.isLeaf(root, leafId, leafIndex, proof);

    take(e, offer, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData, ratifierData);

    assert OfferTree.isLeafNode(leafId);
}
