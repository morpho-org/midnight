// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {
    IEcrecoverRatifier,
    Signature,
    EIP712_DOMAIN_TYPEHASH
} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRatifierTest is BaseTest {
    function buildRatifierData(bytes32 _root, address _signer) internal view returns (bytes memory) {
        Signature memory sig = signature(_root, privateKey[_signer], address(ecrecoverRatifier), 0);
        return abi.encode(sig, _root, 0, new bytes32[](0));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.ratifier = address(ecrecoverRatifier);
        offer.expiry = vm.getBlockTimestamp() + 200;
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

    function testIsRatifiedMakerSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.isRatified(offer, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testIsRatifiedAuthorizedSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(borrower, true, lender);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.isRatified(offer, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testIsRatifiedNotMidnight() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.expectRevert(IEcrecoverRatifier.NotMidnight.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testIsRatifiedUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testIsRatifiedInvalidSignature() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData =
            abi.encode(Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}), _root, 0, new bytes32[](0));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testIsRatifiedWrongRoot() public {
        Offer memory offer = makeOffer(lender);
        bytes32 wrongRoot = keccak256("wrong");
        bytes memory ratifierData = buildRatifierData(wrongRoot, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testIsRatifiedWorksForUnorderedTree() public {
        Offer memory leftOffer = makeOffer(lender);
        Offer memory rightOffer = makeOffer(lender);
        rightOffer.expiry += 1;

        bytes32 leftHash = HashLib.hashOffer(leftOffer);
        bytes32 rightHash = HashLib.hashOffer(rightOffer);
        if (leftHash < rightHash) {
            (leftOffer, rightOffer) = (rightOffer, leftOffer);
            (leftHash, rightHash) = (rightHash, leftHash);
        }

        bytes32 root = HashLib.hashNode(leftHash, rightHash);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leftHash;
        Signature memory sig = signature(root, privateKey[lender], address(ecrecoverRatifier), 1);
        bytes memory ratifierData = abi.encode(sig, root, 1, proof);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.isRatified(rightOffer, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testCancelRootMaker() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.expectEmit(true, true, false, true, address(ecrecoverRatifier));
        emit IEcrecoverRatifier.CancelRoot(lender, lender, _root);
        vm.prank(lender);
        ecrecoverRatifier.cancelRoot(lender, _root);

        assertTrue(ecrecoverRatifier.isRootCanceled(lender, _root));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.RootCanceled.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testCancelRootAuthorizedOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        ecrecoverRatifier.cancelRoot(lender, _root);

        assertTrue(ecrecoverRatifier.isRootCanceled(lender, _root));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.RootCanceled.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }

    function testCancelRootUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.cancelRoot(lender, _root);
    }

    function testIsRatifiedRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(borrower, true, lender);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        // Works while authorized.
        vm.prank(address(midnight));
        ecrecoverRatifier.isRatified(offer, ratifierData);

        // Revoke.
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, false, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }
}
