// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {EcrecoverRatifier} from "../../src/ratifiers/EcrecoverRatifier.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract EcrecoverRatifierHarness is EcrecoverRatifier {
    constructor(address _midnight) EcrecoverRatifier(_midnight) {}

    /// @dev Exposes block.chainid so CVL rules can constrain two envs to have different chain ids
    ///      (CVL does not surface block.chainid as an env field).
    function chainId() external view returns (uint256) {
        return block.chainid;
    }

    /// @dev Recomputes the EIP-712 digest used by onRatify. Used by CVL rules to prove digest
    ///      binding to (root, height, address(this), block.chainid) under optimistic_hashing.
    function digest(bytes32 root, uint256 height) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(UtilsLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        return keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
    }

    /// @dev Same digest computation as `digest`, but with chainId taken as an explicit
    ///      parameter. CVL models `block.chainid` as scene-constant, so two envs cannot
    ///      have different chain ids; this helper sidesteps that limitation. Combined
    ///      with `digestEqualsExplicitAtBlockChainId`, lets us prove the real digest
    ///      depends on chainid.
    function digestWithChainId(bytes32 root, uint256 height, uint256 ci) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(UtilsLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, ci, address(this)));
        return keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
    }

    /// @dev Same digest computation as `digest`, but with the EIP-712 verifier address
    ///      taken as an explicit parameter (instead of address(this)). Lets a CVL rule
    ///      vary the verifier without needing a second harness instance. Combined with
    ///      `digestEqualsExplicitAtThis`, lets us prove the real digest depends on
    ///      address(this).
    function digestWithVerifier(bytes32 root, uint256 height, address verifier) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(UtilsLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, verifier));
        return keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
    }

    /// @dev Exposes the recovered signer to CVL rules. Defers digest computation to the
    ///      `digest` helper so that rules verifying `digest` (binding to root/height/
    ///      verifier/chainid) extend transitively to the recovered signer. The remaining
    ///      manual check is that `onRatify`'s inline digest computation matches `digest`'s
    ///      body — a localized 5-line review.
    function recoverSigner(bytes32 root, bytes memory ratifierData) external view returns (address) {
        (Signature memory sig, uint256 height) = abi.decode(ratifierData, (Signature, uint256));
        bytes32 d = this.digest(root, height);
        return ecrecover(d, sig.v, sig.r, sig.s);
    }
}
