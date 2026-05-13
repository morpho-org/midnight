// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/HashLib.sol";
import {IEcrecoverRatifier, Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRatifierTest is BaseTest {
    function buildRatifierData(bytes32 _root, address _signer) internal view returns (bytes memory) {
        Signature memory sig = signature(_root, privateKey[_signer], address(ecrecoverRatifier), 0);
        return abi.encode(sig, uint256(0), _root, new bytes32[](0));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.ratifier = address(ecrecoverRatifier);
        offer.expiry = block.timestamp + 200;
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

        midnight.setIsAuthorized(lender, borrower, true);
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
        bytes memory ratifierData = abi.encode(
            Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}), uint256(0), _root, new bytes32[](0)
        );

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

    function testCancelRootMaker() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.expectEmit(true, true, false, true, address(ecrecoverRatifier));
        emit IEcrecoverRatifier.CancelRoot(lender, _root);
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
        midnight.setIsAuthorized(lender, borrower, true);

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

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        // Works while authorized.
        vm.prank(address(midnight));
        ecrecoverRatifier.isRatified(offer, ratifierData);

        // Revoke.
        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, false);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.isRatified(offer, ratifierData);
    }
}
