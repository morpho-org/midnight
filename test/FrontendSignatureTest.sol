// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";

// Paste from frontend output.
address constant ACCOUNT = 0x8278e0FdF6036DF01CF23307F0dC6E83d0279C1C;
uint8 constant SIG_V = 27;
bytes32 constant SIG_R = 0x8b31ed2dba1473ba38dab1ef6d0f40e5434ce3e6ecf5d45f8ed16de9d9d229d4;
bytes32 constant SIG_S = 0x6f1809545d188f230375a077418ce4768f4f25f7186f4205711ba075a26cd432;

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
        offer.market.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.market.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.ratifier = RATIFIER;
    }

    function testFrontendSignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultOffer(2);
        offers[1] = defaultOffer(4);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(1);

        bytes32 h0 = HashLib.hashOffer(offers[0]);
        bytes32 h1 = HashLib.hashOffer(offers[1]);
        bytes32 h2 = HashLib.hashOffer(offers[2]);
        bytes32 h3 = HashLib.hashOffer(offers[3]);
        bytes32 left = HashLib.commutativeHash(h0, h1);
        bytes32 right = HashLib.commutativeHash(h2, h3);
        bytes32 _root = HashLib.commutativeHash(left, right);

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = h1;
        proof0[1] = right;
        assertTrue(HashLib.isLeaf(_root, h0, proof0));

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = h0;
        proof1[1] = right;
        assertTrue(HashLib.isLeaf(_root, h1, proof1));

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = h3;
        proof2[1] = left;
        assertTrue(HashLib.isLeaf(_root, h2, proof2));

        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = h2;
        proof3[1] = left;
        assertTrue(HashLib.isLeaf(_root, h3, proof3));

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT, _root, proof0);
        bytes32 result = EcrecoverRatifier(RATIFIER).isRatified(offers[0], ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external pure returns (bool) {
        return signer == ACCOUNT;
    }
}
