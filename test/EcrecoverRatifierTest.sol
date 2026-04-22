// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "../src/interfaces/IEcrecover.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {IEcrecoverRatifier} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRatifierTest is BaseTest {
    function signRoot(bytes32 _root, address _signer) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, _root));
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverRatifier)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[_signer], digest);
        return abi.encode(Signature({v: v, r: r, s: s}));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.ratifier = address(ecrecoverRatifier);
        offer.expiry = block.timestamp + 200;
    }

    function testOnRatifyMakerSigns() public view {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));
        bytes memory ratifierData = signRoot(_root, lender);

        bytes32 result = ecrecoverRatifier.onRatify(offer, _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyAuthorizedSigns() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

        vm.prank(lender);

        midnight.setIsAuthorized(lender, borrower, true);
        bytes memory ratifierData = signRoot(_root, borrower);

        bytes32 result = ecrecoverRatifier.onRatify(offer, _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testOnRatifyUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));
        bytes memory ratifierData = signRoot(_root, borrower);

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);
    }

    function testOnRatifyInvalidSignature() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));
        bytes memory ratifierData = abi.encode(Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}));

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, _root, ratifierData);
    }

    function testOnRatifyWrongRoot() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));
        bytes memory ratifierData = signRoot(_root, lender);

        bytes32 wrongRoot = keccak256("wrong");
        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        ecrecoverRatifier.onRatify(offer, wrongRoot, ratifierData);
    }

    function testOnRatifyRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

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
