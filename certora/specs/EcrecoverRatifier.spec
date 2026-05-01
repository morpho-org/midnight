// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Wallet-decodable-signature soundness for EcrecoverRatifier.onRatify.
//
// Verified against EcrecoverRatifierHarness, which exposes both the recovered
// signer and the EIP-712 digest computed by onRatify. ecrecover is modeled in CVL
// as a deterministic uninterpreted function over (digest, v, r, s); it is NOT
// modeled as injective over digest. We therefore prove signer-binding indirectly:
// digest distinctness across contexts (instance / chainid / height / root) under
// optimistic_hashing, combined with ECDSA injectivity over digest assumed at the
// crypto layer. onRatifySoundness itself only needs ecrecover determinism.

using Midnight as midnight;

methods {
    function MIDNIGHT() external returns (address) envfree;
    function chainId() external returns (uint256);
    function digest(bytes32, uint256) external returns (bytes32);
    function digestWithChainId(bytes32, uint256, uint256) external returns (bytes32);
    function digestWithVerifier(bytes32, uint256, address) external returns (bytes32);
    function recoverSigner(bytes32, bytes) external returns (address);
    function midnight.isAuthorized(address, address) external returns (bool) envfree;
}

/// Same (root, height) with two different verifier addresses produces different
/// digests. Proves address(this) flows into the domain separator — replay across
/// ratifier deployments is impossible (modulo ECDSA injectivity over digest).
/// Uses digestWithVerifier (verifier as parameter) instead of a second harness;
/// connected to the real digest via digestEqualsExplicitAtThis below.
rule digestBoundToVerifier(env e, bytes32 root, uint256 height, address v1, address v2) {
    require v1 != v2;
    assert digestWithVerifier(e, root, height, v1) != digestWithVerifier(e, root, height, v2);
}

/// digestWithVerifier at currentContract equals the real digest. Connects
/// digestBoundToVerifier back to the real onRatify digest computation.
rule digestEqualsExplicitAtThis(env e, bytes32 root, uint256 height) {
    assert digest(e, root, height) == digestWithVerifier(e, root, height, currentContract);
}

/// Same (root, height) on two different chain ids produces different digests.
/// Proves block.chainid flows into the domain separator — cross-chain replay
/// is impossible (modulo ECDSA injectivity over digest). CVL models block.chainid
/// as scene-constant, so we vary chainid via digestWithChainId and connect to
/// the real digest via digestEqualsExplicitAtBlockChainId below.
rule digestBoundToChainId(env e, bytes32 root, uint256 height, uint256 ci1, uint256 ci2) {
    require ci1 != ci2;
    assert digestWithChainId(e, root, height, ci1) != digestWithChainId(e, root, height, ci2);
}

/// digestWithChainId at the env's actual chainid equals the real digest. Connects
/// digestBoundToChainId back to the real onRatify digest computation.
rule digestEqualsExplicitAtBlockChainId(env e, bytes32 root, uint256 height) {
    assert digest(e, root, height) == digestWithChainId(e, root, height, chainId(e));
}

/// Same root with different tree heights produces different digests. Proves
/// offerTreeTypeHash(height) flows into structHash — a sig bound to height H1
/// cannot ratify a tree at height H2 (modulo ECDSA injectivity over digest).
rule digestBoundToHeight(env e, bytes32 root, uint256 h1, uint256 h2) {
    require h1 != h2;
    assert digest(e, root, h1) != digest(e, root, h2);
}

/// Same height with different roots produces different digests. Proves root
/// flows into structHash — a sig bound to root R1 cannot ratify a different
/// root R2 (modulo ECDSA injectivity over digest).
rule digestBoundToRoot(env e, bytes32 root1, bytes32 root2, uint256 height) {
    require root1 != root2;
    assert digest(e, root1, height) != digest(e, root2, height);
}
