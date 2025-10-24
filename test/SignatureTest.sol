// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Signature} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";

import {Test} from "../lib/forge-std/src/Test.sol";

/// @dev Ref implem from OpenZeppelin.
function toEthSignedMessageHash(bytes32 messageHash) pure returns (bytes32 digest) {
    assembly ("memory-safe") {
        mstore(0x00, "\x19Ethereum Signed Message:\n32") // 32 is the bytes-length of messageHash
        mstore(0x1c, messageHash) // 0x1c (28) is the length of the prefix
        digest := keccak256(0x00, 0x3c) // 0x3c is the length of the prefix (0x1c) + messageHash (0x20)
    }
}

contract SignatureTest is Test, MorphoV2 {
    function testFormat(bytes32 root) public pure {
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", root));
        assertEq(toEthSignedMessageHash(root), messageHash);
    }

    function testSigner(bytes32 root, uint256 sk) public pure {
        sk = boundPrivateKey(sk);
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", root));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, messageHash);
        assertEq(_signer(root, Signature({v: v, r: r, s: s})), vm.addr(sk));
    }
}
