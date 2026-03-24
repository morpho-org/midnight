// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Merkle proof: irrelevant to asset computation, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // zeroFloorSub Output do not affects buyerAssets or sellerAssets, so NONDET is safe for this property.
    function UtilsLib.zeroFloorSub(uint256, uint256) internal returns (uint256) => NONDET;

    // Skip obligation creation logic: irrelevant to asset computation, removes collateral loop.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CVL_isHealthy();
}

/// GHOSTS ///

persistent ghost bytes32 ghostId;

persistent ghost address ghostSignerResult;

/// SUMMARY FUNCTIONS ///

function CVL_toId() returns bytes32 {
    return ghostId;
}

function CVL_signer() returns address {
    return ghostSignerResult;
}

function CVL_isHealthy() returns bool {
    return true;
}

/// Offers can be split: taking A obligation units at once yields the same position-related state as taking B then C (where A = B + C).
rule offersCanBeSplit(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    // block.timestamp must fit in uint128 (Midnight.sol:640 casts it; checked in Solidity 0.8.31).
    require to_mathint(e.block.timestamp) < 2 ^ 128;

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    uint256 creditOfBuyer1 = creditOf(ghostId, buyer);
    uint256 debtOfBuyer1 = debtOf(ghostId, buyer);
    uint256 creditOfSeller1 = creditOf(ghostId, seller);
    uint256 debtOfSeller1 = debtOf(ghostId, seller);
    uint256 totalUnits1 = totalUnits(ghostId);
    uint256 consumed1 = consumed(offer.maker, offer.group);

    // Path 2: take B then C from the initial state.
    take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof) at initState;

    take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    assert creditOfBuyer1 == creditOf(ghostId, buyer);
    assert debtOfBuyer1 == debtOf(ghostId, buyer);
    assert creditOfSeller1 == creditOf(ghostId, seller);
    assert debtOfSeller1 == debtOf(ghostId, seller);
    assert totalUnits1 == totalUnits(ghostId);
    assert consumed1 == consumed(offer.maker, offer.group);
}
