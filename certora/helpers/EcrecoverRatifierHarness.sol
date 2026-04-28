// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {EcrecoverRatifier} from "../../src/ratifiers/EcrecoverRatifier.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract EcrecoverRatifierHarness is EcrecoverRatifier {
    constructor(address _midnight) EcrecoverRatifier(_midnight) {}

    /// @dev Replays the digest computation from onRatify and exposes the recovered signer
    ///      so CVL rules can reason about it. Uses the same inputs and the same address(this)
    ///      as onRatify, so ecrecover (uninterpreted in CVL) yields the same signer.
    function recoverSigner(bytes32 root, bytes memory ratifierData) external view returns (address) {
        (Signature memory sig, uint256 height) = abi.decode(ratifierData, (Signature, uint256));
        bytes32 structHash = keccak256(abi.encode(UtilsLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        return ecrecover(digest, sig.v, sig.r, sig.s);
    }
}
