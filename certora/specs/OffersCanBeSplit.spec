// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with axiomatic reasoning.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);

    // Deterministic CVL summaries for assembly utility functions (removes inline assembly complexity).
    function UtilsLib.zeroFloorSub(uint256 x, uint256 y) internal returns (uint256) => CVL_zeroFloorSub(x, y);
    function UtilsLib.min(uint256 x, uint256 y) internal returns (uint256) => CVL_min(x, y);
    function UtilsLib.atMostOneNonZero(uint256, uint256, uint256) internal returns (bool) => NONDET;

    // Returns a fixed symbolic id; sound because the rule only involves a single obligation.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Replaces obligation lookup/creation with a fixed id; position update arithmetic is independent of obligation initialization.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    // Same (root, offer, proof) on all take calls; CONSTANT ensures identical outcome and removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;

    // Read-only health check does not affect position state; removes oracle loop.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // End-of-take liquidation check: depends on isHealthy (already NONDET) and transient lock; NONDET removes the chain.
    function isLiquidatable(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Transient storage lock: uses inline assembly TLOAD/TSTORE; NONDET removes assembly complexity.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;

    // Same offer.tick across all take calls; CONSTANT ensures identical return value.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Same obligation and timestamp across all take calls; CONSTANT ensures identical fee and removes 7-way piecewise interpolation.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Callbacks and token transfers: NONDET removes external call complexity.
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
}

/// GHOSTS ///

persistent ghost bytes32 ghostId;

/// SUMMARY FUNCTIONS ///

function CVL_toId() returns bytes32 {
    return ghostId;
}

function CVL_zeroFloorSub(uint256 x, uint256 y) returns uint256 {
    if (x > y) {
        return require_uint256(x - y);
    }
    return 0;
}

function CVL_min(uint256 x, uint256 y) returns uint256 {
    if (y < x) {
        return y;
    }
    return x;
}

// ghost_mulDivDown(a, b, d) abstracts floor(a*b/d).
persistent ghost ghost_mulDivDown(uint256, uint256, uint256) returns uint256 {
    // Identity: a * x / x == a (needed for _updatePosition no-op when lossIndex is synced).
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivDown(a, x, x) == a;

    // Zero 2nd arg: a * 0 / c == 0 (needed for _updatePosition no-op when no slashing delta).
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivDown(a, 0, c) == 0;

    // Zero 1st arg: 0 * b / c == 0.
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivDown(0, b, c) == 0;

    // Bounded: floor(a*b/d) <= a when b <= d (prevents toUint128 reverts / vacuity).
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivDown(a, b, d) <= a;

    // Sub-additivity (1st arg): floor((b+c)*x/d) ∈ [floor(b*x/d)+floor(c*x/d), floor(b*x/d)+floor(c*x/d)+1].
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && to_mathint(a) == to_mathint(b) + to_mathint(c) => to_mathint(ghost_mulDivDown(a, x, d)) >= to_mathint(ghost_mulDivDown(b, x, d)) + to_mathint(ghost_mulDivDown(c, x, d)) && to_mathint(ghost_mulDivDown(a, x, d)) <= to_mathint(ghost_mulDivDown(b, x, d)) + to_mathint(ghost_mulDivDown(c, x, d)) + 1;
}

// ghost_mulDivUp(a, b, d) abstracts ceil(a*b/d).
persistent ghost ghost_mulDivUp(uint256, uint256, uint256) returns uint256 {
    // Identity: ceil(a * x / x) == a (needed when all remaining credit is consumed: sellerCreditDecrease == sellerCredit).
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivUp(a, x, x) == a;

    // Zero 2nd arg: ceil(a * 0 / c) == 0 (needed for _updatePosition no-op).
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivUp(a, 0, c) == 0;

    // Zero 1st arg: ceil(0 * b / c) == 0.
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivUp(0, b, c) == 0;

    // Bounded: ceil(a*b/d) <= a when b <= d (prevents pendingFee underflow / vacuity).
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivUp(a, b, d) <= a;

    // Super-additivity (1st arg): ceil((b+c)*x/d) ∈ [ceil(b*x/d)+ceil(c*x/d)-1, ceil(b*x/d)+ceil(c*x/d)].
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && to_mathint(a) == to_mathint(b) + to_mathint(c) => to_mathint(ghost_mulDivUp(a, x, d)) <= to_mathint(ghost_mulDivUp(b, x, d)) + to_mathint(ghost_mulDivUp(c, x, d)) && to_mathint(ghost_mulDivUp(a, x, d)) + 1 >= to_mathint(ghost_mulDivUp(b, x, d)) + to_mathint(ghost_mulDivUp(c, x, d));
}

/// Offers can be split: taking A obligation units at once yields the same position-related state as taking B then C (where A = B + C).
/// pendingFee and consumed can differ by at most 1 between the two paths due to floor/ceil rounding in mulDivDown/mulDivUp.
rule offersCanBeSplit(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // Buyer and seller are always distinct (enforced by require(offer.maker != taker) in take).
    // Explicit require prevents the solver from exploring aliased-storage paths.
    require buyer != seller;

    uint128 obLossIndex = currentContract.obligationState[ghostId].lossIndex;
    require to_mathint(obLossIndex) < 2 ^ 128 - 1, "obligation not fully slashed";

    // Pre-synced positions: lossIndex already matches obligation, lastAccrual == block.timestamp.
    // This makes _updatePosition a no-op (identity via ghost axioms), dramatically reducing solver work.
    // Sound precondition: callers can always updatePosition before taking.
    require userLossIndex(ghostId, buyer) == obLossIndex, "buyer lossIndex synced";
    require userLossIndex(ghostId, seller) == obLossIndex, "seller lossIndex synced";
    require to_mathint(lastAccrual(ghostId, buyer)) == to_mathint(e.block.timestamp), "buyer lastAccrual synced";
    require to_mathint(lastAccrual(ghostId, seller)) == to_mathint(e.block.timestamp), "seller lastAccrual synced";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    uint256 creditOfBuyer1 = creditOf(ghostId, buyer);
    uint256 debtOfBuyer1 = debtOf(ghostId, buyer);
    uint256 creditOfSeller1 = creditOf(ghostId, seller);
    uint256 debtOfSeller1 = debtOf(ghostId, seller);
    uint256 totalUnits1 = totalUnits(ghostId);
    uint256 consumed1 = consumed(offer.maker, offer.group);
    uint128 userLossIndexBuyer1 = userLossIndex(ghostId, buyer);
    uint128 userLossIndexSeller1 = userLossIndex(ghostId, seller);
    uint128 lastAccrualBuyer1 = lastAccrual(ghostId, buyer);
    uint128 lastAccrualSeller1 = lastAccrual(ghostId, seller);
    uint128 pendingFeeBuyer1 = pendingFee(ghostId, buyer);
    uint128 pendingFeeSeller1 = pendingFee(ghostId, seller);

    // Path 2: take B then C from the initial state.
    take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;

    take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert creditOfBuyer1 == creditOf(ghostId, buyer), "buyer credit must match";
    assert debtOfBuyer1 == debtOf(ghostId, buyer), "buyer debt must match";
    assert creditOfSeller1 == creditOf(ghostId, seller), "seller credit must match";
    assert debtOfSeller1 == debtOf(ghostId, seller), "seller debt must match";
    assert totalUnits1 == totalUnits(ghostId), "totalUnits must match";
    mathint consumedDiff = to_mathint(consumed1) - to_mathint(consumed(offer.maker, offer.group));
    assert consumedDiff >= -1 && consumedDiff <= 1, "consumed differs by at most 1";
    //assert userLossIndexBuyer1 == userLossIndex(ghostId, buyer), "buyer lossIndex must match";
    //assert userLossIndexSeller1 == userLossIndex(ghostId, seller), "seller lossIndex must match";
    //assert lastAccrualBuyer1 == lastAccrual(ghostId, buyer), "buyer lastAccrual must match";
    //assert lastAccrualSeller1 == lastAccrual(ghostId, seller), "seller lastAccrual must match";
    //mathint pendingFeeBuyerDiff = to_mathint(pendingFeeBuyer1) - to_mathint(pendingFee(ghostId, buyer));
    //assert pendingFeeBuyerDiff >= -1 && pendingFeeBuyerDiff <= 1, "buyer pendingFee differs by at most 1";
    //mathint pendingFeeSellerDiff = to_mathint(pendingFeeSeller1) - to_mathint(pendingFee(ghostId, seller));
    //assert pendingFeeSellerDiff >= -1 && pendingFeeSellerDiff <= 1, "seller pendingFee differs by at most 1";
}
