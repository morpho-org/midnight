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

    function testOnRatifyMakerSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.onRatify(offer, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyAuthorizedSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRatifier.onRatify(offer, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyNotMidnight() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, lender);

        vm.expectRevert(IEcrecoverRatifier.NotMidnight.selector);
        ecrecoverRatifier.onRatify(offer, ratifierData);
    }

    function testOnRatifyUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, ratifierData);
    }

    function testOnRatifyInvalidSignature() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory ratifierData = abi.encode(
            Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}), uint256(0), _root, new bytes32[](0)
        );

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, ratifierData);
    }

    function testOnRatifyWrongRoot() public {
        Offer memory offer = makeOffer(lender);
        bytes32 wrongRoot = keccak256("wrong");
        bytes memory ratifierData = buildRatifierData(wrongRoot, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        ecrecoverRatifier.onRatify(offer, ratifierData);
    }

    function testOnRatifyRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = buildRatifierData(_root, borrower);

        // Works while authorized.
        vm.prank(address(midnight));
        ecrecoverRatifier.onRatify(offer, ratifierData);

        // Revoke.
        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, false);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, ratifierData);
    }
}
