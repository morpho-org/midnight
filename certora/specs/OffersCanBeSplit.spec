// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationState(bytes32 id) external returns (uint128, uint128, uint256, bool, uint32) envfree;

    // Assembly-free math: avoids bitwise overapproximation in SMT.
    function UtilsLib.min(uint256 x, uint256 y) internal returns (uint256) => CVL_min(x, y);
    function UtilsLib.zeroFloorSub(uint256 x, uint256 y) internal returns (uint256) => CVL_zeroFloorSub(x, y);
    function UtilsLib.toUint128(uint256 x) internal returns (uint128) => CVL_toUint128(x);

    // Ghost summaries: removes all nonlinear arithmetic from SMT. Axioms capture only the
    // properties needed for the split proof (identity, zero-input, boundedness).
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);

    // No reentrancy: token transfers and callbacks summarized away.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;

    function _.price() external => NONDET;

    // Gate functions: irrelevant to split property, CONSTANT ensures deterministic gating across all 3 take calls.
    function _.canIncreaseCredit(address) external => CONSTANT;
    function _.canIncreaseDebt(address) external => CONSTANT;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Merkle proof: irrelevant to asset computation, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // Skip obligation creation logic: irrelevant to asset computation, removes collateral loop.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CVL_isHealthy();
}

/// GHOSTS ///

persistent ghost bytes32 ghostId;

persistent ghost uint256 ghostTickPrice;

persistent ghost address ghostSignerResult;

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
    if (x < y) {
        return x;
    }
    return y;
}

function CVL_zeroFloorSub(uint256 x, uint256 y) returns uint256 {
    if (x > y) {
        return require_uint256(x - y);
    }
    return 0;
}

function CVL_toUint128(uint256 x) returns uint128 {
    require to_mathint(x) <= to_mathint(max_uint128);
    return require_uint128(x);
}

// ghost_mulDivDown(a, b, d) abstracts floor(a*b/d).
// Only the axioms below are assumed — no nonlinear arithmetic in the SMT formula.
persistent ghost ghost_mulDivDown(uint256, uint256, uint256) returns uint256 {
    // Identity: a * x / x == a (needed for _updatePosition no-op when lossIndex is synced).
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivDown(a, x, x) == a;

    // Zero 2nd arg: a * 0 / c == 0 (needed for _updatePosition no-op when no slashing delta).
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivDown(a, 0, c) == 0;

    // Zero 1st arg: 0 * b / c == 0.
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivDown(0, b, c) == 0;

    // Bounded: floor(a*b/d) <= a when b <= d (prevents toUint128 reverts / vacuity).
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivDown(a, b, d) <= a;
}

// ghost_mulDivUp(a, b, d) abstracts ceil(a*b/d).
persistent ghost ghost_mulDivUp(uint256, uint256, uint256) returns uint256 {
    // Zero 2nd arg: ceil(a * 0 / c) == 0 (needed for _updatePosition no-op).
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivUp(a, 0, c) == 0;

    // Zero 1st arg: ceil(0 * b / c) == 0.
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivUp(0, b, c) == 0;

    // Bounded: ceil(a*b/d) <= a when b <= d (prevents pendingFee underflow / vacuity).
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivUp(a, b, d) <= a;
}

/// Offers can be split: taking A obligation units at once yields the same position-related state as taking B then C (where A = B + C).
rule offersCanBeSplit(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    // block.timestamp must fit in uint128 (Midnight.sol:640 casts it; checked in Solidity 0.8.31).
    require to_mathint(e.block.timestamp) < 2 ^ 128;

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // Valid obligation state: not fully slashed (Midnight.sol:66 documents this limitation).
    uint128 obLossIndex;
    _, obLossIndex, _, _, _ = obligationState(ghostId);
    require to_mathint(obLossIndex) < 2 ^ 128 - 1, "obligation not fully slashed";

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
