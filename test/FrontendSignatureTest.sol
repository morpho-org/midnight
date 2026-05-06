// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

// Paste from frontend output.
address constant ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
uint8 constant SIG_V = 28;
bytes32 constant SIG_R = 0xb9b9bbc9871e19caccd05beff7c335263e6fc81ea4b29d4ab65c260cf6b977ae;
bytes32 constant SIG_S = 0x335181240405f44f94ff143bc841ce19120907dad81d5cbb489ff9292ce7c478;

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
uint256 constant HEIGHT = 2;

contract FrontendSignatureTest is Test {
    function setUp() public {
        vm.chainId(1);
        EcrecoverRatifier impl = new EcrecoverRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultOffer(uint8 number) internal pure returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        offer.obligation.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.obligation.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.ratifier = RATIFIER;
        offer.maker = ACCOUNT;
    }

    function testFrontendSignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultOffer(1);
        offers[1] = defaultOffer(2);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

        bytes32 h0 = UtilsLib.hashOffer(offers[0]);
        bytes32 h1 = UtilsLib.hashOffer(offers[1]);
        bytes32 h2 = UtilsLib.hashOffer(offers[2]);
        bytes32 h3 = UtilsLib.hashOffer(offers[3]);
        bytes32 left = UtilsLib.commutativeHash(h0, h1);
        bytes32 right = UtilsLib.commutativeHash(h2, h3);
        bytes32 _root = UtilsLib.commutativeHash(left, right);

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = h1;
        proof0[1] = right;
        assertTrue(UtilsLib.isLeaf(_root, h0, proof0));

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = h0;
        proof1[1] = right;
        assertTrue(UtilsLib.isLeaf(_root, h1, proof1));

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = h3;
        proof2[1] = left;
        assertTrue(UtilsLib.isLeaf(_root, h2, proof2));

        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = h2;
        proof3[1] = left;
        assertTrue(UtilsLib.isLeaf(_root, h3, proof3));

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT, _root, proof0);
        bytes32 result = EcrecoverRatifier(RATIFIER).onRatify(offers[0], ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }
}
