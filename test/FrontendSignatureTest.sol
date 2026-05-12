// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/HashLib.sol";

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
uint256 constant HEIGHT = 2;
uint256 constant PRIVATE_KEY = 0xa11ce;

contract FrontendSignatureTest is Test {
    address internal account;

    function setUp() public {
        vm.chainId(1);
        account = vm.addr(PRIVATE_KEY);
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
        offers[0] = defaultOffer(2);
        offers[1] = defaultOffer(1);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

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

        bytes32 _session;
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, RATIFIER));
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeWithSessionTypeHash(HEIGHT), _session, _root));
        bytes32 messageHash = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        Signature memory _signature;
        (_signature.v, _signature.r, _signature.s) = vm.sign(PRIVATE_KEY, messageHash);

        bytes memory ratifierData = abi.encode(_signature, HEIGHT, _root, proof0, _session);
        bytes32 result = EcrecoverRatifier(RATIFIER).isRatified(offers[0], ratifierData);
        assertEq(result, CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external view returns (bool) {
        return signer == account;
    }

    function session(address) external pure returns (bytes32) {
        return bytes32(0);
    }
}
