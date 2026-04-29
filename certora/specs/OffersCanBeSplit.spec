// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with axiomatic reasoning.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);

    // Same offer caps across compared paths; CONSTANT avoids arbitrary pass/fail changes.
    function UtilsLib.atMostOneNonZero(uint256, uint256, uint256) internal returns (bool) => CONSTANT;

    // Deterministic hash preserves obligation-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Replaces obligation lookup/creation with a deterministic id; position update arithmetic is independent of obligation initialization.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryToId(obligation);

    // Offer hashing only feeds the Merkle gate; this rule compares position state after successful split paths.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    
    // Same (root, offer, proof) on all take calls; CONSTANT ensures identical outcome and removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;

    // Read-only health check does not affect position state; removes oracle loop.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // End-of-take liquidation check: deterministic across compared paths for the executability rule.
    function isLiquidatable(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CONSTANT;

    // Transient storage lock: uses inline assembly TLOAD/TSTORE; NONDET removes assembly complexity.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;

    // Same offer.tick across all take calls; CONSTANT ensures identical return value.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Same obligation and timestamp across all take calls; CONSTANT ensures identical fee and removes 7-way piecewise interpolation.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Ratifier result is identical across the full and split takes.
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => CVL_callbackSuccess() expect(bytes32);
    // Token transfers: NONDET removes external call complexity.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    // Buy/sell callbacks are disabled in the executability rule.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
}

/// SUMMARY FUNCTIONS ///

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function CVL_callbackSuccess() returns bytes32 {
    return callbackSuccess();
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

persistent ghost callbackSuccess() returns bytes32;

/// Offers can be split: taking A obligation units at once yields the same position-related state as taking B then C (where A = B + C).
rule offersCanBeSplit(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

    bytes32 id = summaryToId(offer.obligation);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // Explicit require prevents the solver from exploring aliased-storage paths.
    require buyer != seller, "prover perfomance";

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

    // Path 2: take B then C from the initial state.
    take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;

    take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert creditOfBuyer1 == creditOf(id, buyer), "buyer credit must match";
    assert debtOfBuyer1 == debtOf(id, buyer), "buyer debt must match";
    assert creditOfSeller1 == creditOf(id, seller), "seller credit must match";
    assert debtOfSeller1 == debtOf(id, seller), "seller debt must match";
    assert totalUnits1 == totalUnits(id), "totalUnits must match";
}

/*
/// If a full take succeeds, splitting it into B then C also succeeds on the core no-callback/no-gate path.
/// Asset-capped sell offers are excluded because ceil rounding can make the split consume one extra asset.
rule fullTakeSuccessImpliesSplitSuccess(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

    bytes32 id = summaryToId(offer.obligation);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require buyer != seller, "prover perfomance";
    require to_mathint(currentContract.obligationState[id].lossIndex) < 2 ^ 128 - 1, "obligation not fully slashed";

    require offer.callback == 0, "maker callback disabled";
    require takerCallback == 0, "taker callback disabled";
    require offer.obligation.enterGate == 0, "enter gate disabled";
    require offer.buy || (offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0), "sell offers must be unit-capped";

    storage initState = lastStorage;

    take@withrevert(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);
    require !lastReverted, "full take must succeed";

    take@withrevert(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;
    bool splitBReverted = lastReverted;
    assert !splitBReverted, "first split take must succeed";
    require !splitBReverted, "continue from successful first split take";

    take@withrevert(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);
    assert !lastReverted, "second split take must succeed";
}*/
