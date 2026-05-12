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
import {HashLib} from "../src/ratifiers/HashLib.sol";
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

    function testIsRatifiedValidSignature(uint256 privateKey) public {
        privateKey = boundPrivateKey(privateKey);
        address maker = vm.addr(privateKey);

        Offer memory offer;
        offer.maker = maker;
        bytes32 root = HashLib.hashOffer(offer);
        bytes32 _session = midnight.session(maker);

        Signature memory signature = signature(root, privateKey, address(ecrecoverRatifier), 0, _session);

        vm.prank(maker);
        midnight.setIsAuthorized(maker, address(ecrecoverRatifier), true);

        vm.prank(address(midnight));
        bytes32 result =
            ecrecoverRatifier.isRatified(offer, abi.encode(signature, uint256(0), root, new bytes32[](0), _session));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testIsRatifiedInvalidSignature() public {
        Offer memory offer;
        offer.maker = borrower;
        bytes32 root = HashLib.hashOffer(offer);

        Signature memory badSig;
        bytes32 _session = midnight.session(borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        ecrecoverRatifier.isRatified(offer, abi.encode(badSig, uint256(0), root, new bytes32[](0), _session));
    }
}
