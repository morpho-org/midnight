// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function ratified(address user, bytes32 root) external returns (bool) envfree;

    function _.price() external => NONDET;
    function _.onBuy(Midnight.Offer, address, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Offer, address, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;

    // Summaries for internals irrelevant to ratification properties.
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function Midnight.isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function Midnight.signer(bytes32 root, Midnight.Signature memory) internal returns (address) => signerSummary(root, _);
    function Midnight.domainSeparator() internal returns (bytes32) => NONDET;
}

persistent ghost ghostSigner(bytes32) returns address;

function signerSummary(bytes32 root, Midnight.Signature s) returns address {
    return ghostSigner(root);
}

/// Every successful take requires maker consent via at least one of:
///   1. Maker signed directly (offerSigner == offer.maker)
///   2. Maker authorized the signer (isAuthorized[offer.maker][offerSigner])
///   3. Maker authorized the callback (isAuthorized[offer.maker][offer.callback])
///   4. Maker pre-ratified the root (ratified[offer.maker][root])
rule takeRequiresMakerConsent(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    bool makerSigned = ghostSigner(root) == offer.maker;
    bool makerAuthorizedSigner = isAuthorized(offer.maker, ghostSigner(root));
    bool makerAuthorizedCallback = isAuthorized(offer.maker, offer.callback);
    bool rootRatified = ratified(offer.maker, root);

    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert makerSigned || makerAuthorizedSigner || makerAuthorizedCallback || rootRatified;
}

/// ISOLATION ///

/// setAuthorizedWithSig only changes isAuthorized for the (authorizer, authorizee) in the authorization struct.
rule setAuthorizedWithSigIsolation(env e, Midnight.Authorization authorization, Midnight.Signature signature, address otherUser, address otherAuthorized) {
    require otherUser != authorization.authorizer || otherAuthorized != authorization.authorizee;

    bool before = isAuthorized(otherUser, otherAuthorized);
    setAuthorizedWithSig(e, authorization, signature);
    assert isAuthorized(otherUser, otherAuthorized) == before;
}

/// setRatified only changes the specified (onBehalf, root) pair.
rule setRatifiedIsolation(env e, address onBehalf, bytes32 root, bool val, address otherUser, bytes32 otherRoot) {
    require otherUser != onBehalf || otherRoot != root;

    bool before = ratified(otherUser, otherRoot);
    setRatified(e, onBehalf, root, val);
    assert ratified(otherUser, otherRoot) == before;
}
