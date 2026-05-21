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
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {BaseTest} from "./BaseTest.sol";

contract SignatureTest is BaseTest {
    function domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, verifyingContract));
    }

    function signature(bytes32 _root, uint256 _privateKey, address verifyingContract, uint256 height)
        internal
        view
        returns (Signature memory)
    {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), _root));
        bytes32 messageHash = keccak256(bytes.concat("\x19\x01", domainSeparator(verifyingContract), structHash));
        Signature memory _sig;
        (_sig.v, _sig.r, _sig.s) = vm.sign(_privateKey, messageHash);
        return _sig;
    }

    function testDomainSeparator() public view {
        bytes32 _domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverRatifier)));
        bytes32 expectedDomainSeparator = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)",
            abi.encode(block.chainid, address(ecrecoverRatifier))
        );
        assertEq(_domainSeparator, expectedDomainSeparator);
    }

    function testIsRatifiedValidSignature(uint256 privateKey) public {
        privateKey = boundPrivateKey(privateKey);
        address maker = vm.addr(privateKey);

        Offer memory offer;
        offer.maker = maker;
        bytes32 root = HashLib.hashOffer(offer);

        Signature memory _sig = signature(root, privateKey, address(ecrecoverRatifier), 0);

        vm.prank(maker);
        midnight.setIsAuthorized(address(ecrecoverRatifier), true, maker);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.isRatified(offer, abi.encode(_sig, root, 0, new bytes32[](0)));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testIsRatifiedInvalidSignature() public {
        Offer memory offer;
        offer.maker = borrower;
        bytes32 root = HashLib.hashOffer(offer);

        Signature memory badSig;

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        ecrecoverRatifier.isRatified(offer, abi.encode(badSig, root, 0, new bytes32[](0)));
    }
}
