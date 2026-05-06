// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Same offer.tick across all take calls; CONSTANT ensures identical return value.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Summarize toId: deterministic hash preserves obligation-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Offer hashing only feeds the Merkle gate; this rule asserts asset arithmetic on successful split paths.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;

    // Merkle proof: irrelevant to asset computation, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;

    // Skip obligation creation logic: irrelevant to asset computation, removes collateral loop.
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => summaryToId(obligation);

    // Read-only health check does not affect return values; removes oracle loop.
    // Also covers the end-of-take seller-liquidatable require, which is inlined and uses isHealthy directly.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Transient storage lock: uses inline assembly TLOAD/TSTORE; irrelevant to return values.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with axiomatic reasoning.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghost_mulDivUp(a, b, d);
}

/// GHOSTS ///

// ghost_mulDivDown(a, b, d) abstracts floor(a*b/d).
persistent ghost ghost_mulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivDown(a, x, x) == a;
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivDown(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivDown(0, b, c) == 0;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivDown(a, b, d) <= a;

    // Sub-additivity (1st arg): floor((b+c)*x/d) ∈ [floor(b*x/d)+floor(c*x/d), floor(b*x/d)+floor(c*x/d)+1].
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && to_mathint(a) == to_mathint(b) + to_mathint(c) => to_mathint(ghost_mulDivDown(a, x, d)) >= to_mathint(ghost_mulDivDown(b, x, d)) + to_mathint(ghost_mulDivDown(c, x, d)) && to_mathint(ghost_mulDivDown(a, x, d)) <= to_mathint(ghost_mulDivDown(b, x, d)) + to_mathint(ghost_mulDivDown(c, x, d)) + 1;
}

// ghost_mulDivUp(a, b, d) abstracts ceil(a*b/d).
persistent ghost ghost_mulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 x. x != 0 => ghost_mulDivUp(a, x, x) == a;
    axiom forall uint256 a. forall uint256 c. c != 0 => ghost_mulDivUp(a, 0, c) == 0;
    axiom forall uint256 b. forall uint256 c. c != 0 => ghost_mulDivUp(0, b, c) == 0;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d != 0 && b <= d => ghost_mulDivUp(a, b, d) <= a;

    // Super-additivity (1st arg): ceil((b+c)*x/d) ∈ [ceil(b*x/d)+ceil(c*x/d)-1, ceil(b*x/d)+ceil(c*x/d)].
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && to_mathint(a) == to_mathint(b) + to_mathint(c) => to_mathint(ghost_mulDivUp(a, x, d)) <= to_mathint(ghost_mulDivUp(b, x, d)) + to_mathint(ghost_mulDivUp(c, x, d)) && to_mathint(ghost_mulDivUp(a, x, d)) + 1 >= to_mathint(ghost_mulDivUp(b, x, d)) + to_mathint(ghost_mulDivUp(c, x, d));
}

/// SUMMARY FUNCTIONS ///

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

/// Splitting an offer does not punish the maker or favor the taker on asset amounts.
/// When offer.buy (maker=buyer, taker=seller): Maker pays less or equal (within 1 wei) when split, taker receives less or equal when split.
/// When !offer.buy (maker=seller, taker=buyer): Maker receives more or equal ((within 1 wei) when split, taker pays more or equal when split.
rule splitDoesNotPunishMakerOrFavorTaker(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    // block.timestamp must fit in uint128 (Midnight.sol casts it).
    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

    // Solver hints: instantiate the sub/super-additivity axioms for the specific A/B/C split.
    require forall uint256 b. forall uint256 d. d != 0 => to_mathint(ghost_mulDivDown(obligationUnitsA, b, d)) >= to_mathint(ghost_mulDivDown(obligationUnitsB, b, d)) + to_mathint(ghost_mulDivDown(obligationUnitsC, b, d)) && to_mathint(ghost_mulDivDown(obligationUnitsA, b, d)) <= to_mathint(ghost_mulDivDown(obligationUnitsB, b, d)) + to_mathint(ghost_mulDivDown(obligationUnitsC, b, d)) + 1, "solver hint: instantiation of ghost_mulDivDown sub-additivity axiom for A/B/C";
    require forall uint256 b. forall uint256 d. d != 0 => to_mathint(ghost_mulDivUp(obligationUnitsA, b, d)) <= to_mathint(ghost_mulDivUp(obligationUnitsB, b, d)) + to_mathint(ghost_mulDivUp(obligationUnitsC, b, d)) && to_mathint(ghost_mulDivUp(obligationUnitsA, b, d)) + 1 >= to_mathint(ghost_mulDivUp(obligationUnitsB, b, d)) + to_mathint(ghost_mulDivUp(obligationUnitsC, b, d)), "solver hint: instantiation of ghost_mulDivUp super-additivity axiom for A/B/C";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    uint256 buyerAssetsA;
    uint256 sellerAssetsA;
    buyerAssetsA, sellerAssetsA, _ = take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    // Path 2: take B then C from the initial state.
    uint256 buyerAssetsB;
    uint256 sellerAssetsB;
    buyerAssetsB, sellerAssetsB, _ = take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof) at initState;

    uint256 buyerAssetsC;
    uint256 sellerAssetsC;
    buyerAssetsC, sellerAssetsC, _ = take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    // Maker is buyer: splitting saves them at most 1 wei (tight rounding bound).
    assert offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) <= to_mathint(buyerAssetsA);
    assert offer.buy => to_mathint(buyerAssetsA) <= to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) + 1;

    // Taker is seller: splitting should not make them receive more.
    assert offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) <= to_mathint(sellerAssetsA);
    assert offer.buy => to_mathint(sellerAssetsA) <= to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) + 1;

    // Maker is seller: splitting should not make them receive less.
    assert !offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) >= to_mathint(sellerAssetsA);
    assert !offer.buy => to_mathint(sellerAssetsA) + 1 >= to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC);

    // Taker is buyer: splitting should not make them pay less.
    assert !offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) >= to_mathint(buyerAssetsA);
    assert !offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) <= to_mathint(buyerAssetsA) + 1;
}
