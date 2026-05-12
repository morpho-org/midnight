// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer, CollateralParams, Obligation} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/HashLib.sol";
import {MerkleLib} from "../src/ratifiers/MerkleLib.sol";
import {Midnight} from "../src/Midnight.sol";

// Anvil account #0 — its known private key produced the SIG_* values below.
address constant ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
uint8 constant SIG_V = 27;
bytes32 constant SIG_R = 0x33648c0ee0ec55dbe22b51bf8d44107fe38afc2634187abecee1f28fdcbed9d1;
bytes32 constant SIG_S = 0x7b8269c32d9b8c54fdd60db17bcb0065a96e8a736d8b2d164e724dc44468dd5b;

// Fixed addresses keep offer ids and the EIP-712 verifyingContract deterministic across runs.
address constant MIDNIGHT_ADDR = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

uint256 constant HEIGHT = 2;

contract FrontendSignatureTest is Test {
    Midnight internal midnight;

    function setUp() public {
        vm.chainId(1);
        Midnight tmp = new Midnight();
        vm.etch(MIDNIGHT_ADDR, address(tmp).code);
        midnight = Midnight(MIDNIGHT_ADDR);

        EcrecoverRatifier impl = new EcrecoverRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultOffer(uint8 number) internal view returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        Obligation memory obligation;
        obligation.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        obligation.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.ratifier = RATIFIER;
        offer.id = midnight.toId(obligation);
    }

    function testFrontendSignatureVerification() public {
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
