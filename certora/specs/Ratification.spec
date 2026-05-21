// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function Utils.hashOffer(Midnight.Offer) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    function _.isRatified(Midnight.Offer, bytes) external => DISPATCHER(true);
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;

    // Capture HashLib.isLeaf's return; needed by `isRatifiedRequiresIsLeaf` to assert isRatified gates on a merkle check.
    function HashLib.isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof) internal returns (bool) => isLeafCapture(root, leafHash, leafIndex, proof);

    function HashLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function HashLib.offerTreeTypeHash(uint256) internal returns (bytes32) => NONDET;

    // Summaries for internals irrelevant to ratification properties.
    function IdLib.toId(Midnight.Market memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
}

function summaryHashOffer(Midnight.Offer offer) returns bytes32 {
    return Utils.hashOffer(offer);
}

// Captures whether HashLib.isLeaf was called and returned true during the current rule.
// Used by `isRatifiedRequiresIsLeaf` to assert that every successful isRatified gates on a merkle check.
persistent ghost bool isLeafReturnedTrue;

function isLeafCapture(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] proof) returns bool {
    bool ret;
    if (ret) {
        isLeafReturnedTrue = true;
    }
    return ret;
}

/// Every successful take requires the maker to have authorized the ratifier.
rule takeRequiresMakerConsent(env e, Midnight.Offer offer, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, bytes ratifierData) {
    bool makerAuthorizedRatifier = isAuthorized(offer.maker, offer.ratifier);

    take(e, offer, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData, ratifierData);

    assert makerAuthorizedRatifier;
}

/// address(0) can't authorize another account, because it can't call
/// and setIsAuthorized requires msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender].
strong invariant addressZeroCantAuthorize(address authorized)
    !isAuthorized(0, authorized)
    {
        preserved with (env e) {
            require e.msg.sender != 0, "address(0) can't call";
            requireInvariant addressZeroCantAuthorize(e.msg.sender);
        }
    }

/// No successful take can use address(0) as maker.
rule takeRequiresNonZeroMaker(env e, Midnight.Offer offer, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, bytes ratifierData) {
    requireInvariant addressZeroCantAuthorize(offer.ratifier);

    take(e, offer, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData, ratifierData);
    assert offer.maker != 0;
}

/// Every successful isRatified call implies HashLib.isLeaf was invoked and returned true. Verified by dispatch across all linked ratifier implementations.
rule isRatifiedRequiresIsLeaf(env e, address ratifierAddr, Midnight.Offer offer, bytes ratifierData) {
    require !isLeafReturnedTrue, "fresh capture state";

    bytes32 result = ratifierAddr.isRatified(e, offer, ratifierData);
    require result == Utils.callbackSuccess(), "isRatified succeeded";

    assert isLeafReturnedTrue, "ratifier must have called HashLib.isLeaf that returned true";
}
