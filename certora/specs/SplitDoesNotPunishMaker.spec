// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    // Deterministic id: every obligation maps to the same ghostId.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => CVL_toId();

    // Deterministic price: same tick always gives the same offerPrice.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => CVL_tickToPrice();

    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // same inputs always return the same value across all 3 take calls.
    function tradingFee(bytes32, uint256) internal returns (uint256) => CONSTANT;

    // Deterministic signer: must return the same address across all 3 take calls.
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();

    // Always healthy: irrelevant to the split property, avoids oracle + collateral loop complexity.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => CVL_isHealthy();

    // No reentrancy: token transfers and callbacks summarized away.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
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

/// Splitting an offer does not punish the maker on asset amounts.
/// When maker is buyer (offer.buy), buyerAssets uses mulDivDown so splitting should not increase what the maker pays: assets(B) + assets(C) <= assets(A).
/// When maker is seller (!offer.buy), sellerAssets uses mulDivUp so splitting should not decrease what the maker receives: assets(B) + assets(C) >= assets(A).
rule splitDoesNotPunishMaker(env e, uint256 obligationUnitsA, uint256 obligationUnitsB, uint256 obligationUnitsC, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require obligationUnitsA == require_uint256(obligationUnitsB + obligationUnitsC);

    storage initState = lastStorage;

    // Path 1: take the full amount A.
    uint256 buyerAssetsA;
    uint256 sellerAssetsA;
    buyerAssetsA, sellerAssetsA, _ = take(e, obligationUnitsA, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    // Path 2: take B then C from the initial state.
    uint256 buyerAssetsB;
    uint256 sellerAssetsB;
    buyerAssetsB, sellerAssetsB, _ = take(e, obligationUnitsB, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof) at initState;

    uint256 buyerAssetsC;
    uint256 sellerAssetsC;
    buyerAssetsC, sellerAssetsC, _ = take(e, obligationUnitsC, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    // Maker is buyer: splitting should not make them pay more.
    assert offer.buy => to_mathint(buyerAssetsB) + to_mathint(buyerAssetsC) <= to_mathint(buyerAssetsA);

    // Maker is seller: splitting should not make them receive less.
    assert !offer.buy => to_mathint(sellerAssetsB) + to_mathint(sellerAssetsC) >= to_mathint(sellerAssetsA);
}
