// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Over-approximate view functions.
    function IdLib.toId(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function _.isRatified(Midnight.Offer offer, bytes, address taker) external => recordRatification(calledContract, offer, taker) expect(bytes32);
}

// Persistent so that the unresolved calls after the ratification, such as callbacks and token transfers, do not erase it.

persistent ghost mathint ratificationCalls;

persistent ghost address ratifiedBy;

persistent ghost address ratifiedMaker;

persistent ghost address ratifiedCallback;

persistent ghost address ratifiedTaker;

persistent ghost bytes32 ratificationResult;

function recordRatification(address ratifier, Midnight.Offer offer, address taker) returns bytes32 {
    bool reverts;
    if (reverts) {
        revert();
    }
    bytes32 result;
    ratificationCalls = ratificationCalls + 1;
    ratifiedBy = ratifier;
    ratifiedMaker = offer.maker;
    ratifiedCallback = offer.callback;
    ratifiedTaker = taker;
    ratificationResult = result;
    return result;
}

// Every successful take requires the maker to have authorized the ratifier.
rule takeRequiresMakerConsent(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    bool makerAuthorizedRatifier = isAuthorized(offer.maker, offer.ratifier);

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert makerAuthorizedRatifier;
}

// address(0) can't authorize another account, because it can't call and setIsAuthorized requires msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender].
strong invariant addressZeroCantAuthorize(address authorized)
    !isAuthorized(0, authorized)
    {
        preserved with (env e) {
            require e.msg.sender != 0, "address(0) can't call";
            requireInvariant addressZeroCantAuthorize(e.msg.sender);
        }
    }

// No successful take can use address(0) as maker.
rule takeRequiresNonZeroMaker(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    requireInvariant addressZeroCantAuthorize(offer.ratifier);

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    assert offer.maker != 0;
}

// Every successful take asks the offer's ratifier to ratify the offer for the taker, and requires it to return CALLBACK_SUCCESS.
// Of the offer seen by the ratifier, only the maker and the callback are checked: they are the fields the take summary in morpho-org/vault-v2#1361 relies on.
rule takeRequiresRatifierSuccess(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    require ratificationCalls == 0, "no ratification before take";

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert ratificationCalls == 1;
    assert ratifiedBy == offer.ratifier;
    assert ratifiedMaker == offer.maker && ratifiedCallback == offer.callback && ratifiedTaker == taker;
    assert ratificationResult == Utils.callbackSuccess();
}

// No successful take has the maker as taker.
rule takeRequiresDistinctMakerAndTaker(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert offer.maker != taker;
}
