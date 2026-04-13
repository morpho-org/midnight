// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Same offer.tick across all take calls; CONSTANT ensures identical return value.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CONSTANT;

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Merkle proof: irrelevant to asset computation, removes hashing loop.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => CONSTANT;

    // zeroFloorSub feeds into timeToMaturity (only used by tradingFee, already CONSTANT) and buyerCreditIncrease (affects position state, not return values). NONDET is safe for this property.
    function UtilsLib.zeroFloorSub(uint256, uint256) internal returns (uint256) => NONDET;

    // Skip obligation creation logic: irrelevant to asset computation, removes collateral loop.
    function touchObligation(Midnight.Obligation memory) internal returns (bytes32) => CVL_toId();

    // Same obligation and timestamp across all take calls; CONSTANT ensures identical fee and removes piecewise interpolation.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Read-only health check does not affect return values; removes oracle loop.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

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

/// Splitting an offer does not punish the maker or favor the taker on asset amounts.
/// When offer.buy (maker=buyer, taker=seller): Maker pays less or equal when split, taker receives less or equal when split.
/// When !offer.buy (maker=seller, taker=buyer): Maker receives more or equal when split, taker pays more or equal when split.
rule splitDoesNotPunishMakerOrFavorTaker(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC), "obligationUnitsA must be equal to obligationUnitsB + obligationUnitsC";

    storage initState = lastStorage;

    // block.timestamp must fit in uint128 (Midnight.sol:640 casts it; checked in Solidity 0.8.31).
    require to_mathint(e.block.timestamp) < 2 ^ 128, "block.timestamp must fit in uint128";

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

    // Maker is buyer: splitting should not make them pay more.
    assert offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) <= to_mathint(buyerAssetsA);

    // Taker is seller: splitting should not make them receive more.
    assert offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) <= to_mathint(sellerAssetsA);

    // Maker is seller: splitting should not make them receive less.
    assert !offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) >= to_mathint(sellerAssetsA);

    // Taker is buyer: splitting should not make them pay less.
    assert !offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) >= to_mathint(buyerAssetsA);
}
