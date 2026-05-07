// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with lightweight axioms.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);

    // Same offer caps across compared paths; CONSTANT avoids arbitrary pass/fail changes.
    function UtilsLib.atMostOneNonZero(uint256, uint256, uint256) internal returns (bool) => CONSTANT;

    // Deterministic hash preserves obligation-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Replaces obligation lookup/creation with a deterministic id; this rule starts from an arbitrary valid storage state.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryToId(obligation);

    // Offer hashing only feeds the Merkle gate; this rule compares position state after successful split paths.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;

    // Same (root, offer, proof) on all take calls; CONSTANT ensures identical outcome and removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;

    // Force the same return value across the three calls so the seller-liquidatable check either fires on both paths or neither.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CONSTANT;

    // Transient storage lock: uses inline assembly TLOAD/TSTORE; NONDET removes assembly complexity.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
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

    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

    bytes32 id = summaryToId(offer.obligation);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // Redundant with the SelfTake() revert; kept as a solver hint to break storage aliasing.
    require buyer != seller;

    uint128 obLossIndex = currentContract.obligationState[id].lossIndex;
    require to_mathint(obLossIndex) < 2 ^ 128 - 1, "obligation not fully slashed";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    uint256 creditOfBuyer1 = creditOf(id, buyer);
    uint256 debtOfBuyer1 = debtOf(id, buyer);
    uint256 creditOfSeller1 = creditOf(id, seller);
    uint256 debtOfSeller1 = debtOf(id, seller);
    uint256 totalUnits1 = totalUnits(id);

    // take() never writes obligationState.lossIndex; _updatePosition mirrors it into position.lossIndex.
    uint128 buyerLossIndex1 = userLossIndex(id, buyer);
    uint128 sellerLossIndex1 = userLossIndex(id, seller);

    // lastAccrual is set to block.timestamp by _updatePosition; same env across both paths.
    uint128 buyerLastAccrual1 = lastAccrual(id, buyer);
    uint128 sellerLastAccrual1 = lastAccrual(id, seller);

    // _updatePosition accrues before the principal move; the split-C accrual sees the same timestamp.
    uint128 continuousFeeCredit1 = currentContract.obligationState[id].continuousFeeCredit;

    // Regression guards: take() never writes obligationState.withdrawable or position.activatedCollaterals.
    uint128 withdrawable1 = currentContract.obligationState[id].withdrawable;
    uint128 buyerActivated1 = currentContract.position[id][buyer].activatedCollaterals;
    uint128 sellerActivated1 = currentContract.position[id][seller].activatedCollaterals;

    // Path 2: take B then C from the initial state.
    take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;

    take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert creditOfBuyer1 == creditOf(id, buyer), "buyer credit must match";
    assert debtOfBuyer1 == debtOf(id, buyer), "buyer debt must match";
    assert creditOfSeller1 == creditOf(id, seller), "seller credit must match";
    assert debtOfSeller1 == debtOf(id, seller), "seller debt must match";
    assert totalUnits1 == totalUnits(id), "totalUnits must match";
    assert buyerLossIndex1 == userLossIndex(id, buyer), "buyer lossIndex must match";
    assert sellerLossIndex1 == userLossIndex(id, seller), "seller lossIndex must match";
    assert buyerLastAccrual1 == lastAccrual(id, buyer), "buyer lastAccrual must match";
    assert sellerLastAccrual1 == lastAccrual(id, seller), "seller lastAccrual must match";
    assert continuousFeeCredit1 == currentContract.obligationState[id].continuousFeeCredit, "continuousFeeCredit must match";
    assert withdrawable1 == currentContract.obligationState[id].withdrawable, "withdrawable must match";
    assert buyerActivated1 == currentContract.position[id][buyer].activatedCollaterals, "buyer activatedCollaterals must match";
    assert sellerActivated1 == currentContract.position[id][seller].activatedCollaterals, "seller activatedCollaterals must match";
}
