// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Signature} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {ROOT_TYPEHASH} from "../src/libraries/ConstantsLib.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

contract SignatureTest is Test, Midnight {
    function testSigner(bytes32 root, uint256 privateKey) public view {
        privateKey = boundPrivateKey(privateKey);
        bytes32 domainSeparator = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)", abi.encode(block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        assertEq(signer(root, Signature({v: v, r: r, s: s})), vm.addr(privateKey));
    }

    function testDomainSeparator() public view {
        bytes32 expectedDomainSeparator = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)", abi.encode(block.chainid, address(this))
        );
        assertEq(domainSeparator(), expectedDomainSeparator);
    }
}
