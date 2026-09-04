// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {EcrecoverRateRatifier} from "../src/ratifiers/EcrecoverRateRatifier.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";

// Paste from frontend output (sign-root.ts).
address constant ACCOUNT = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
uint8 constant SIG_V = 27;
bytes32 constant SIG_R = 0xeb511490094f44ed91b79ebc436cc7c7e6d282e657bc39797a98ce2dd3826be0;
bytes32 constant SIG_S = 0x58ec81dc273626bd4ea660bd5682a5860eed1e37927ee8cce469ef7261f9c183;

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

contract FrontendSignatureTest is Test {
    function setUp() public {
        vm.chainId(1);
        EcrecoverRatifier impl = new EcrecoverRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultOffer(uint8 number) internal pure returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        offer.market.chainId = 1;
        offer.market.midnight = address(0);
        offer.market.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.market.collateralParams = collateralParams;
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
        bytes32 left = HashLib.hashNode(h0, h1);
        bytes32 right = HashLib.hashNode(h2, h3);
        bytes32 _root = HashLib.hashNode(left, right);

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = h1;
        proof0[1] = right;
        assertTrue(HashLib.isLeaf(_root, h0, 0, proof0));

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = h0;
        proof1[1] = right;
        assertTrue(HashLib.isLeaf(_root, h1, 1, proof1));

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = h3;
        proof2[1] = left;
        assertTrue(HashLib.isLeaf(_root, h2, 2, proof2));

        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = h2;
        proof3[1] = left;
        assertTrue(HashLib.isLeaf(_root, h3, 3, proof3));

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), _root, 0, proof0);
        bytes32 result = EcrecoverRatifier(RATIFIER).isRatified(offers[0], ratifierData, address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external pure returns (bool) {
        return signer == ACCOUNT;
    }
}

// Paste from frontend output (sign-rate-root.ts).
uint256 constant RATE = 3170979198; // 0.1e18 / 365 days
uint8 constant RATE_SIG_V = 28;
bytes32 constant RATE_SIG_R = 0x7ebdc647a0b0a6fae4935023b9908839e9f7eea39dbcc0ca0d4755b3624ddc06;
bytes32 constant RATE_SIG_S = 0x031551f84fedd4789c50ec7bc62305d048e33c233ba352b842496d074d0cb46c;

contract FrontendRateSignatureTest is Test {
    function setUp() public {
        vm.chainId(1);
        EcrecoverRateRatifier impl = new EcrecoverRateRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
    }

    function defaultRateOffer(uint8 number) internal pure returns (Offer memory offer) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        offer.market.chainId = 1;
        offer.market.midnight = address(0);
        offer.market.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.market.collateralParams = collateralParams;
        offer.expiry = 2 ** 32;
        offer.buy = true;
        offer.ratifier = RATIFIER;
    }

    function testFrontendRateSignatureVerification() public view {
        Offer[4] memory offers;
        offers[0] = defaultRateOffer(1);
        offers[1] = defaultRateOffer(2);
        offers[2] = defaultRateOffer(3);
        offers[3] = defaultRateOffer(4);

        bytes32 h0 = HashLib.hashRateOffer(offers[0], RATE, RATE);
        bytes32 h1 = HashLib.hashRateOffer(offers[1], RATE, RATE);
        bytes32 h2 = HashLib.hashRateOffer(offers[2], RATE, RATE);
        bytes32 h3 = HashLib.hashRateOffer(offers[3], RATE, RATE);
        bytes32 left = HashLib.hashNode(h0, h1);
        bytes32 right = HashLib.hashNode(h2, h3);
        bytes32 _root = HashLib.hashNode(left, right);

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = h1;
        proof0[1] = right;
        assertTrue(HashLib.isLeaf(_root, h0, 0, proof0));

        bytes memory ratifierData =
            abi.encode(Signature({v: RATE_SIG_V, r: RATE_SIG_R, s: RATE_SIG_S}), _root, uint256(0), proof0, RATE, RATE);
        bytes32 result = EcrecoverRateRatifier(RATIFIER).isRatified(offers[0], ratifierData, address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external pure returns (bool) {
        return signer == ACCOUNT;
    }
}
