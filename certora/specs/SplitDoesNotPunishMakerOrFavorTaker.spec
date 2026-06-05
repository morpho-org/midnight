// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Ghost summaries for mulDivDown/mulDivUp: replaces nonlinear 256-bit arithmetic with axiomatic reasoning.
    // Axioms are discharged by rules in MulDiv.spec (see references on the ghosts below).
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghostMulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => ghostMulDivUp(a, b, d);

    // Summarize toId: deterministic hash preserves market-to-id relationship without adding assumptions.
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

/// GHOSTS ///

// ghostMulDivDown(a, b, d) abstracts floor(a*b/d). Axioms are proven as rules in MulDiv.spec.
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    // Sub-additivity (1st arg): floor((b+c)*x/d) ∈ [floor(b*x/d)+floor(c*x/d), floor(b*x/d)+floor(c*x/d)+1].
    // Lower bound proven by mulDivAddDownDown, upper bound by mulDivAddDownDownTight in MulDiv.spec.
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && a == b + c => ghostMulDivDown(a, x, d) >= ghostMulDivDown(b, x, d) + ghostMulDivDown(c, x, d) && ghostMulDivDown(a, x, d) <= ghostMulDivDown(b, x, d) + ghostMulDivDown(c, x, d) + 1;
}

// ghostMulDivUp(a, b, d) abstracts ceil(a*b/d). Axioms are proven as rules in MulDiv.spec.
persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    // Super-additivity (1st arg): ceil((b+c)*x/d) ∈ [ceil(b*x/d)+ceil(c*x/d)-1, ceil(b*x/d)+ceil(c*x/d)].
    // Lower bound proven by mulDivAddUpUpTight, upper bound by mulDivAddUpUp in MulDiv.spec.
    axiom forall uint256 a. forall uint256 b. forall uint256 c. forall uint256 x. forall uint256 d. d != 0 && a == b + c => ghostMulDivUp(a, x, d) <= ghostMulDivUp(b, x, d) + ghostMulDivUp(c, x, d) && ghostMulDivUp(a, x, d) + 1 >= ghostMulDivUp(b, x, d) + ghostMulDivUp(c, x, d);
}

/// SUMMARY FUNCTIONS ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

/// Splitting an offer does not punish the maker or favor the taker on asset amounts.
/// When offer.buy (maker=buyer, taker=seller): Maker pays less or equal (within 1 wei) when split, taker receives less or equal when split.
/// When !offer.buy (maker=seller, taker=buyer): Maker receives more or equal (within 1 wei) when split, taker pays more or equal when split.
rule splitDoesNotPunishMakerOrFavorTaker(env e, uint256 unitsA, uint256 unitsB, uint256 unitsC, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, Midnight.Offer offer, bytes ratifierData) {
    require unitsA == require_uint256(unitsB + unitsC), "unitsA must be equal to unitsB + unitsC";

    require e.block.timestamp <= max_uint128, "block.timestamp must fit in uint128";

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    uint256 buyerAssetsA;
    uint256 sellerAssetsA;
    buyerAssetsA, sellerAssetsA = take(e, offer, ratifierData, unitsA, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    // Maker's offer cap consumed after path 1.
    uint256 consumedAfterA = currentContract.consumed[offer.maker][offer.group];

    // Protocol fee accrued in storage after path 1: incremented by buyerAssets - sellerAssets per take.
    uint256 claimableAfterA = currentContract.claimableSettlementFee[offer.market.loanToken];

    // Path 2: take B then C from the initial state.
    uint256 buyerAssetsB;
    uint256 sellerAssetsB;
    buyerAssetsB, sellerAssetsB = take(e, offer, ratifierData, unitsB, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData) at initState;

    uint256 buyerAssetsC;
    uint256 sellerAssetsC;
    buyerAssetsC, sellerAssetsC = take(e, offer, ratifierData, unitsC, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    // Maker's offer cap consumed after path 2.
    uint256 consumedAfterBC = currentContract.consumed[offer.maker][offer.group];

    // Protocol fee accrued in storage after path 2.
    uint256 claimableAfterBC = currentContract.claimableSettlementFee[offer.market.loanToken];

    // Maker is buyer: splitting should not make them pay more.
    assert offer.buy => buyerAssetsB + buyerAssetsC <= buyerAssetsA;
    assert offer.buy => buyerAssetsA <= buyerAssetsB + buyerAssetsC + 1;

    // Taker is seller: splitting should not make them receive more.
    assert offer.buy => sellerAssetsB + sellerAssetsC <= sellerAssetsA;
    assert offer.buy => sellerAssetsA <= sellerAssetsB + sellerAssetsC + 1;

    // Maker is seller: splitting should not make them receive less.
    assert !offer.buy => sellerAssetsB + sellerAssetsC >= sellerAssetsA;
    assert !offer.buy => sellerAssetsA + 1 >= sellerAssetsB + sellerAssetsC;

    // Taker is buyer: splitting should not make them pay less.
    assert !offer.buy => buyerAssetsB + buyerAssetsC >= buyerAssetsA;
    assert !offer.buy => buyerAssetsB + buyerAssetsC <= buyerAssetsA + 1;

    // Maker's offer cap consumption can change by at most 1 wei across splits in maxAssets mode
    // (bounded by the asset deviation), and is exact in maxUnits mode (consumed += units, with A == B + C).
    assert consumedAfterA <= consumedAfterBC + 1;
    assert consumedAfterBC <= consumedAfterA + 1;
    assert offer.maxAssets == 0 => consumedAfterA == consumedAfterBC;

    // Protocol fee storage delta (claimableSettlementFee += buyerAssets - sellerAssets per take) can change by at most 1 wei across splits.
    assert claimableAfterA <= claimableAfterBC + 1;
    assert claimableAfterBC <= claimableAfterA + 1;
}
