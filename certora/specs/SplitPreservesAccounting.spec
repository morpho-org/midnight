// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with lightweight axioms.
    // Axioms are discharged by rules in MulDiv.spec (see references on the ghosts below).
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghostMulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghostMulDivUp(a, b, d);

    // Deterministic hash preserves market-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Assume that the markets are already created.
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Pure helper called with identical args across the three takes; CONSTANT collapses
    // its bit / hashing / arithmetic complexity (no behavioral abstraction).
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Over-approximate view functions.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;

    // Over-approximate transient storage.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;
}

/// SUMMARY FUNCTIONS ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

// ghostMulDivDown(a, b, d) abstracts floor(a*b/d). Axioms are proven as rules in MulDiv.spec.
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    // Identity (b=d=x): floor(a*x/x) = a. Proven by mulDivIdentity in MulDiv.spec.
    axiom forall uint256 a. forall uint256 x. x != 0 => ghostMulDivDown(a, x, x) == a;

    // floor(a*0/c) = 0. Proven by mulDivZero in MulDiv.spec.
    axiom forall uint256 a. forall uint256 c. c != 0 => ghostMulDivDown(a, 0, c) == 0;
}

// ghostMulDivUp(a, b, d) abstracts ceil(a*b/d).
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

/// Taking A units at once preserves position accounting versus taking B then C, where A = B + C.
/// This is intentionally not an economic no-advantage rule; asset rounding is covered in SplitDoesNotPunishMakerOrFavorTaker.spec.
rule splitPreservesAccounting(env e, uint256 unitsA, uint256 unitsB, uint256 unitsC, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, Midnight.Offer offer, bytes ratifierData) {
    require unitsA == require_uint256(unitsB + unitsC), "unitsA must be equal to unitsB + unitsC";

    require e.block.timestamp <= max_uint128, "block.timestamp must fit in uint128 (prover helper)";

    bytes32 id = summaryToId(offer.market);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require buyer != seller, "take() already verifies but it's for prover performance";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    take(e, offer, ratifierData, unitsA, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    uint128 creditOfBuyer1 = creditOf(id, buyer);
    uint128 debtOfBuyer1 = debtOf(id, buyer);
    uint128 creditOfSeller1 = creditOf(id, seller);
    uint128 debtOfSeller1 = debtOf(id, seller);
    uint128 totalUnits1 = totalUnits(id);
    uint128 buyerLossFactor1 = lastLossFactor(id, buyer);
    uint128 sellerLossFactor1 = lastLossFactor(id, seller);
    uint128 continuousFeeCredit1 = currentContract.marketState[id].continuousFeeCredit;

    // lastAccrual is set to block.timestamp by _updatePosition; same env across both paths.
    uint128 buyerLastAccrual1 = lastAccrual(id, buyer);
    uint128 sellerLastAccrual1 = lastAccrual(id, seller);

    // Path 2: take B then C from the initial state.
    take(e, offer, ratifierData, unitsB, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData) at initState;

    take(e, offer, ratifierData, unitsC, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert creditOfBuyer1 == creditOf(id, buyer);
    assert debtOfBuyer1 == debtOf(id, buyer);
    assert creditOfSeller1 == creditOf(id, seller);
    assert debtOfSeller1 == debtOf(id, seller);
    assert totalUnits1 == totalUnits(id);
    assert buyerLossFactor1 == lastLossFactor(id, buyer);
    assert sellerLossFactor1 == lastLossFactor(id, seller);
    assert buyerLastAccrual1 == lastAccrual(id, buyer);
    assert sellerLastAccrual1 == lastAccrual(id, seller);
    assert continuousFeeCredit1 == currentContract.marketState[id].continuousFeeCredit;
}
