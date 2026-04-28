// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Wallet-decodable-signature soundness for EcrecoverRatifier.onRatify.
// Verified against EcrecoverRatifierHarness which exposes the recovered signer.
// ecrecover is modeled by Certora as a deterministic uninterpreted function, so
// onRatify and recoverSigner — both built from the same digest inputs and the
// same address(this) — yield the same signer.

using Midnight as midnight;

methods {
    function MIDNIGHT() external returns (address) envfree;
    function recoverSigner(bytes32, bytes) external returns (address);
    function midnight.isAuthorized(address, address) external returns (bool) envfree;
}

/// onRatify success ⟹ recovered signer is non-zero AND
/// (signer == offer.maker OR isAuthorized[offer.maker][signer]).
rule onRatifySoundness(env e, Midnight.Offer offer, bytes32 root, bytes ratifierData) {
    address signer = recoverSigner(e, root, ratifierData);

    onRatify(e, offer, root, ratifierData);

    assert signer != 0;
    assert signer == offer.maker || midnight.isAuthorized(offer.maker, signer);
}

/// onRatify reverts when ecrecover returns address(0) (malformed signature).
rule onRatifyRevertsOnInvalidSig(env e, Midnight.Offer offer, bytes32 root, bytes ratifierData) {
    address signer = recoverSigner(e, root, ratifierData);
    require signer == 0;

    onRatify@withrevert(e, offer, root, ratifierData);

    assert lastReverted;
}

/// onRatify reverts when signer is neither maker nor authorized by maker.
rule onRatifyRevertsOnUnauthorized(env e, Midnight.Offer offer, bytes32 root, bytes ratifierData) {
    address signer = recoverSigner(e, root, ratifierData);
    require signer != 0;
    require signer != offer.maker;
    require !midnight.isAuthorized(offer.maker, signer);

    onRatify@withrevert(e, offer, root, ratifierData);

    assert lastReverted;
}
