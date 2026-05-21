// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with lightweight axioms.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);

    // Deterministic hash preserves obligation-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    // Assume that the obligations are already created.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryToId(obligation);

    // Pure helpers called with identical args across the three takes; CONSTANT collapses
    // their bit / hashing / arithmetic complexity (no behavioral abstraction).
    function UtilsLib.atMostOneNonZero(uint256, uint256, uint256) internal returns (bool) => CONSTANT;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Force the same return value across the three calls so the seller-liquidatable check either fires on both paths or neither.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CONSTANT;

    // Over-approximate transient storage.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;

    // Offer hashing only feeds the Merkle gate; this rule compares position state after successful split paths.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
}

/// SUMMARY FUNCTIONS ///

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

// ghost_mulDivDown(a, b, d) abstracts floor(a*b/d).
persistent ghost ghost_mulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivDown(a, x, x) == a;
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivDown(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivDown(0, b, c) == 0;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivDown(a, b, d) <= a;
}

// ghost_mulDivUp(a, b, d) abstracts ceil(a*b/d).
persistent ghost ghost_mulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivUp(a, x, x) == a;
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivUp(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivUp(0, b, c) == 0;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivUp(a, b, d) <= a;
}

/// Taking A obligation units at once preserves principal accounting versus taking B then C, where A = B + C.
/// This is intentionally not an economic no-advantage rule; asset rounding is covered in SplitDoesNotPunishMakerOrFavorTaker.spec.
rule splitPreservesPrincipalAccounting(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    require e.block.timestamp <= max_uint128, "block.timestamp must fit in uint128 (prover helper)";

    bytes32 id = summaryToId(offer.obligation);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require buyer != seller, "take() already verifies but it's for prover performance";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    uint256 creditOfBuyer1 = creditOf(id, buyer);
    uint256 debtOfBuyer1 = debtOf(id, buyer);
    uint256 creditOfSeller1 = creditOf(id, seller);
    uint256 debtOfSeller1 = debtOf(id, seller);
    uint256 totalUnits1 = totalUnits(id);

    // take() never writes obligationState.lossFactor; _updatePosition mirrors it into position.lastLossFactor.
    uint128 buyerLossFactor1 = lastLossFactor(id, buyer);
    uint128 sellerLossFactor1 = lastLossFactor(id, seller);

    // lastAccrual is set to block.timestamp by _updatePosition; same env across both paths.
    uint128 buyerLastAccrual1 = lastAccrual(id, buyer);
    uint128 sellerLastAccrual1 = lastAccrual(id, seller);

    // _updatePosition is idempotent at lastAccrual == block.timestamp, so split-C adds 0 to the accumulator.
    uint128 continuousFeeCredit1 = currentContract.obligationState[id].continuousFeeCredit;

    // Path 2: take B then C from the initial state.
    take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;

    take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert creditOfBuyer1 == creditOf(id, buyer);
    assert debtOfBuyer1 == debtOf(id, buyer);
    assert creditOfSeller1 == creditOf(id, seller);
    assert debtOfSeller1 == debtOf(id, seller);
    assert totalUnits1 == totalUnits(id);
    assert buyerLossFactor1 == lastLossFactor(id, buyer);
    assert sellerLossFactor1 == lastLossFactor(id, seller);
    assert buyerLastAccrual1 == lastAccrual(id, buyer);
    assert sellerLastAccrual1 == lastAccrual(id, seller);
    assert continuousFeeCredit1 == currentContract.obligationState[id].continuousFeeCredit;
}
