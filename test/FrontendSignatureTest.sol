// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/interfaces/IEcrecover.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

// Paste from frontend output.
address constant ACCOUNT = 0xFDa6883171208B36122229505FB2D6F30c052311;
uint8 constant SIG_V = 28;
bytes32 constant SIG_R = 0x5ba4989d3c22a4981ea9e3a1dd4aa77c16b646eaf6fae3393978f3d752efe9b8;
bytes32 constant SIG_S = 0x340377683b31c78acd43b763af192383b26d09e6a3d73f3784585bda30d11250;

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
uint256 constant HEIGHT = 2;

contract FrontendSignatureTest is Test {
    function setUp() public {
        EcrecoverRatifier impl = new EcrecoverRatifier(address(0));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultOffer(uint8 number) internal pure returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        offer.obligation.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.obligation.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.ratifier = RATIFIER;
    }

    function sortOffers(Offer[4] memory offers) internal pure returns (Offer[4] memory) {
        bytes32[4] memory hashes;
        for (uint256 i = 0; i < 4; i++) {
            hashes[i] = UtilsLib.hashOffer(offers[i]);
        }

        // Sort left pair (indices 0,1).
        if (hashes[0] > hashes[1]) {
            (offers[0], offers[1]) = (offers[1], offers[0]);
            (hashes[0], hashes[1]) = (hashes[1], hashes[0]);
        }

        // Sort right pair (indices 2,3).
        if (hashes[2] > hashes[3]) {
            (offers[2], offers[3]) = (offers[3], offers[2]);
            (hashes[2], hashes[3]) = (hashes[3], hashes[2]);
        }

        // Sort inner nodes: commutativeHash(left) <= commutativeHash(right).
        bytes32 left = UtilsLib.commutativeHash(hashes[0], hashes[1]);
        bytes32 right = UtilsLib.commutativeHash(hashes[2], hashes[3]);
        if (left > right) {
            (offers[0], offers[1], offers[2], offers[3]) = (offers[2], offers[3], offers[0], offers[1]);
        }

        return offers;
    }

    function testFrontendSignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultOffer(1);
        offers[1] = defaultOffer(2);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

        offers = sortOffers(offers);
        console.log(offers[0].obligation.loanToken);
        console.log(offers[1].obligation.loanToken);
        console.log(offers[2].obligation.loanToken);
        console.log(offers[3].obligation.loanToken);

        bytes32 h0 = UtilsLib.hashOffer(offers[0]);
        bytes32 h1 = UtilsLib.hashOffer(offers[1]);
        bytes32 h2 = UtilsLib.hashOffer(offers[2]);
        bytes32 h3 = UtilsLib.hashOffer(offers[3]);
        bytes32 left = UtilsLib.commutativeHash(h0, h1);
        bytes32 right = UtilsLib.commutativeHash(h2, h3);
        bytes32 _root = UtilsLib.commutativeHash(left, right);

        // Verify each offer is a leaf of the root.
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

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT);
        offers[0].maker = ACCOUNT;
        bytes32 result = EcrecoverRatifier(RATIFIER).onRatify(offers[0], _root, ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }
}
