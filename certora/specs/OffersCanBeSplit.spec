// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;

    // Deterministic price: same tick always gives the same offerPrice.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CVL_tickToPrice();

    // Deterministic signer: must return the same address across all 3 take calls.
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();

    // Always healthy: irrelevant to the split property, avoids oracle + collateral loop complexity.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CVL_isHealthy();

    // Same inputs always return the same value across all 3 take calls.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Skip obligation creation logic: only sets created/fees/continuousFee which don't affect credit/debt/totalUnits/consumed.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    // Merkle proof: irrelevant to position state, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // Assembly-free math: avoids bitwise overapproximation in SMT.
    function UtilsLib.min(uint256 x, uint256 y) internal returns (uint256) => CVL_min(x, y);
    function UtilsLib.zeroFloorSub(uint256 x, uint256 y) internal returns (uint256) => CVL_zeroFloorSub(x, y);

    // Ghost math: removes nonlinear multiplication from SMT queries.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    // No reentrancy: token transfers and callbacks summarized away.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;

    function _.price() external => NONDET;

    // Gate functions: irrelevant to split property, CONSTANT ensures deterministic gating across all 3 take calls.
    function _.canIncreaseCredit(address) external => CONSTANT;
    function _.canIncreaseDebt(address) external => CONSTANT;

    // Public auto-generated getter (uint16[7] fees excluded by Solidity).
    function obligationState(bytes32 id) external returns (uint128, uint128, uint256, bool, uint32) envfree;
}

/// GHOSTS ///

persistent ghost bytes32 ghostId;

persistent ghost uint256 ghostTickPrice;

persistent ghost address ghostSignerResult;

// mulDivDown(a,b,d) = floor(a*b/d): identity when b==d, zero when a==0 or b==0.
persistent ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 x. x != 0 => CVL_mulDivDown(a, x, x) == a;
    axiom forall uint256 a. forall uint256 c. c != 0 => CVL_mulDivDown(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => CVL_mulDivDown(0, b, c) == 0;
}

// mulDivUp(a,b,d) = ceil(a*b/d): zero when a==0 or b==0.
persistent ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 c. c != 0 => CVL_mulDivUp(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => CVL_mulDivUp(0, b, c) == 0;
}

/// SUMMARY FUNCTIONS ///

function CVL_toId() returns bytes32 {
    return ghostId;
}

function CVL_tickToPrice() returns uint256 {
    return ghostTickPrice;
}

function CVL_signer() returns address {
    return ghostSignerResult;
}

function CVL_isHealthy() returns bool {
    return true;
}

function CVL_min(uint256 x, uint256 y) returns uint256 {
    if (x < y) { return x; }
    return y;
}

function CVL_zeroFloorSub(uint256 x, uint256 y) returns uint256 {
    if (x > y) { return require_uint256(x - y); }
    return 0;
}

/// Offers can be split: taking A obligation units at once yields the same position-related state as taking B then C (where A = B + C).
rule offersCanBeSplit(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    // block.timestamp must fit in uint128 (Midnight.sol:640 casts it; checked in Solidity 0.8.31).
    require to_mathint(e.block.timestamp) < 2^128;

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // Valid obligation state: not fully slashed (Midnight.sol:66 documents this limitation).
    uint128 obLossIndex;
    _, obLossIndex, _, _, _ = obligationState(ghostId);
    require to_mathint(obLossIndex) < 2^128 - 1, "obligation not fully slashed";

    // Valid position state: position lossIndex <= obligation lossIndex (monotonicity invariant).
    require to_mathint(userLossIndex(ghostId, buyer)) <= to_mathint(obLossIndex), "buyer lossIndex consistent";
    require to_mathint(userLossIndex(ghostId, seller)) <= to_mathint(obLossIndex), "seller lossIndex consistent";

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
