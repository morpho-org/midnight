// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {
    IEcrecoverRatifier,
    Signature,
    EIP712_DOMAIN_TYPEHASH
} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract SignatureTest is BaseTest {
    function testDomainSeparator() public view {
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverRatifier)));
        bytes32 expectedDomainSeparator = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)",
            abi.encode(block.chainid, address(ecrecoverRatifier))
        );
        assertEq(domainSeparator, expectedDomainSeparator);
    }

    function testOnRatifyValidSignature(bytes32 root, uint256 privateKey) public {
        privateKey = boundPrivateKey(privateKey);
        address maker = vm.addr(privateKey);

        Signature memory signature = signature(root, privateKey, address(ecrecoverRatifier), 0);

        Offer memory offer;
        offer.maker = maker;

        vm.prank(maker);

        midnight.setIsAuthorized(maker, address(ecrecoverRatifier), true);
        bytes32 result = ecrecoverRatifier.onRatify(offer, root, abi.encode(signature, uint256(0)));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyInvalidSignature(bytes32 root) public {
        Offer memory offer;
        offer.maker = borrower;

        Signature memory badSig;

        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        ecrecoverRatifier.onRatify(offer, root, abi.encode(badSig, uint256(0)));
    }
}
