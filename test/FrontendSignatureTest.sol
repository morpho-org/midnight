// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/HashLib.sol";
import {MerkleLib} from "../src/ratifiers/MerkleLib.sol";

// Paste from frontend output.
address constant ACCOUNT = 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A;
uint8 constant SIG_V = 28;
bytes32 constant SIG_R = 0x6fd764bae7dca042f26e70b37fcfc17a9acf14f22258a49ba2089972710ffa38;
bytes32 constant SIG_S = 0x26564af47fc62ac20989d7acb7b8dbe2fdf2600820a56f1eac942e8e10218e32;

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
    }

    function testFrontendSignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultOffer(1);
        offers[1] = defaultOffer(2);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

        bytes32 h0 = HashLib.hashOffer(offers[0]);
        bytes32 h1 = HashLib.hashOffer(offers[1]);
        bytes32 h2 = HashLib.hashOffer(offers[2]);
        bytes32 h3 = HashLib.hashOffer(offers[3]);
        bytes32 left = MerkleLib.commutativeHash(h0, h1);
        bytes32 right = MerkleLib.commutativeHash(h2, h3);
        bytes32 _root = MerkleLib.commutativeHash(left, right);

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = h1;
        proof0[1] = right;
        assertTrue(MerkleLib.isLeaf(_root, h0, proof0));

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = h0;
        proof1[1] = right;
        assertTrue(MerkleLib.isLeaf(_root, h1, proof1));

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = h3;
        proof2[1] = left;
        assertTrue(MerkleLib.isLeaf(_root, h2, proof2));

        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = h2;
        proof3[1] = left;
        assertTrue(MerkleLib.isLeaf(_root, h3, proof3));

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT, _root, proof0);
        bytes32 result = EcrecoverRatifier(RATIFIER).isRatified(offers[0], ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external pure returns (bool) {
        return signer == ACCOUNT;
    }
}
