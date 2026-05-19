// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.isRatified(Midnight.Offer, bytes) external => DISPATCHER(true);
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function HashLib.isLeaf(bytes32, bytes32, uint256, bytes32[] memory) internal returns (bool) => NONDET;
    function HashLib.offerTreeTypeHash(uint256) internal returns (bytes32) => NONDET;
    function HashLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;

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

/// Every successful take requires the maker to have authorized the ratifier.
rule takeRequiresMakerConsent(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    bool makerAuthorizedRatifier = isAuthorized(offer.maker, offer.ratifier);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);

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
rule takeRequiresNonZeroMaker(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) {
    requireInvariant addressZeroCantAuthorize(offer.ratifier);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData);
    assert offer.maker != 0;
}
