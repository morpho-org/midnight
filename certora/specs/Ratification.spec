// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Over-approximate view functions.
    function IdLib.toId(Midnight.Market memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
}

/// Every successful take requires the maker to have authorized the ratifier.
rule takeRequiresMakerConsent(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    bool makerAuthorizedRatifier = isAuthorized(offer.maker, offer.ratifier);

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

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
rule takeRequiresNonZeroMaker(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) {
    requireInvariant addressZeroCantAuthorize(offer.ratifier);

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    assert offer.maker != 0;
}
