// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {IEcrecoverRatifier, Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRatifierTest is BaseTest {
    function signRoot(bytes32 _root, address _signer) internal view returns (bytes memory) {
        Signature memory sig = signature(_root, privateKey[_signer], address(ecrecoverRatifier), 0);
        return abi.encode(sig, uint256(0));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.ratifier = address(ecrecoverRatifier);
        offer.expiry = block.timestamp + 200;
    }

    function testOnRatifyMakerSigns() public view {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);
        bytes memory ratifierData = signRoot(_root, lender);

        bytes32 result = ecrecoverRatifier.onRatify(offer, _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyAuthorizedSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = signRoot(_root, borrower);

        bytes32 result = ecrecoverRatifier.onRatify(offer, _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);
        bytes memory ratifierData = signRoot(_root, borrower);

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);
    }

    function testOnRatifyInvalidSignature() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);
        bytes memory ratifierData =
            abi.encode(Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}), uint256(0));

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);
    }

    function testOnRatifyWrongRoot() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);
        bytes memory ratifierData = signRoot(_root, lender);

        bytes32 wrongRoot = keccak256("wrong");
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, wrongRoot, ratifierData);
    }

    function testOnRatifyRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = UtilsLib.hashOffer(offer);

        vm.prank(lender);

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = signRoot(_root, borrower);

        // Works while authorized.
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);

        // Revoke.
        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, false);

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);
    }
}
