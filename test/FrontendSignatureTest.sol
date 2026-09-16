// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {PriceRatifierV1} from "../src/ratifiers/PriceRatifierV1.sol";
import {RateRatifierV1} from "../src/ratifiers/RateRatifierV1.sol";
import {Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {SET_IS_ROOT_RATIFIED_SUCCESS} from "../src/ratifiers/interfaces/IRatifiersV1Common.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";

// Paste from frontend output (sign-root.ts), "EcrecoverRatifier — OfferTree".
address constant ACCOUNT = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
uint8 constant SIG_V = 27;
bytes32 constant SIG_R = 0xeb511490094f44ed91b79ebc436cc7c7e6d282e657bc39797a98ce2dd3826be0;
bytes32 constant SIG_S = 0x58ec81dc273626bd4ea660bd5682a5860eed1e37927ee8cce469ef7261f9c183;

// Paste from frontend output (sign-root.ts), "PriceRatifierV1 — SetIsRootRatified".
uint8 constant PRICE_SIG_V = 27;
bytes32 constant PRICE_SIG_R = 0x9a6ef6f41ff1bf784fc9505a69eafe7c7020727c0eba4cdfbc676ae5661acc25;
bytes32 constant PRICE_SIG_S = 0x3bceff070ad18ffed2cf7b2373bb91085f084af3af5de4b172ec7fbbed4a01d6;

// Paste from frontend output (sign-root.ts), "RateRatifierV1 — SetIsRootRatified".
uint8 constant RATE_SIG_V = 27;
bytes32 constant RATE_SIG_R = 0x86fe42783681bc6ffc1c074a9002d3978842669ef5fd1bc44376bb1b92a8fbd2;
bytes32 constant RATE_SIG_S = 0x47f8edf014b66502c8c532353128bccc986cfcf82a5be76685dff5b9ce44c3df;

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
address constant PRICE_RATIFIER = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;
address constant RATE_RATIFIER = 0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd;
address constant ALLOWED_TAKER = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;

uint256 constant HEIGHT = 2;
uint128 constant NONCE = 0;
uint256 constant DEADLINE = 2 ** 32;

contract FrontendSignatureTest is Test {
    function setUp() public {
        vm.chainId(1);
        EcrecoverRatifier impl = new EcrecoverRatifier(address(this));
        vm.etch(RATIFIER, address(impl).code);
        PriceRatifierV1 priceImpl = new PriceRatifierV1(address(this));
        vm.etch(PRICE_RATIFIER, address(priceImpl).code);
        RateRatifierV1 rateImpl = new RateRatifierV1(address(this));
        vm.etch(RATE_RATIFIER, address(rateImpl).code);
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

    /// @dev The V1 ratifiers look their ratification up under offer.maker, and RateRatifierV1 checks the offer's
    /// price against its rate, so their offers are the maker's own and priced to be takeable.
    function v1Offer(uint8 number) internal pure returns (Offer memory offer) {
        offer = defaultOffer(number);
        offer.maker = ACCOUNT;
        offer.buy = true;
    }

    function testFrontendSignaturePriceRatifierV1() public {
        bytes32 h0 = HashLib.hashPriceRatifierV1Offer(v1Offer(1), ALLOWED_TAKER);
        bytes32 h1 = HashLib.hashPriceRatifierV1Offer(v1Offer(2), ALLOWED_TAKER);
        bytes32 h2 = HashLib.hashPriceRatifierV1Offer(v1Offer(3), ALLOWED_TAKER);
        bytes32 h3 = HashLib.hashPriceRatifierV1Offer(v1Offer(4), ALLOWED_TAKER);
        bytes32 left = HashLib.hashNode(h0, h1);
        bytes32 right = HashLib.hashNode(h2, h3);
        bytes32 _root = HashLib.hashNode(left, right);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = right;
        assertTrue(HashLib.isLeaf(_root, h0, 0, proof));

        proof[0] = h0;
        assertTrue(HashLib.isLeaf(_root, h1, 1, proof));

        proof[0] = h3;
        proof[1] = left;
        assertTrue(HashLib.isLeaf(_root, h2, 2, proof));

        proof[0] = h2;
        assertTrue(HashLib.isLeaf(_root, h3, 3, proof));

        vm.prank(ACCOUNT);
        bytes32 result = PriceRatifierV1(PRICE_RATIFIER)
            .setIsRootRatifiedWithSig(
                ACCOUNT, _root, HEIGHT, true, NONCE, DEADLINE, PRICE_SIG_V, PRICE_SIG_R, PRICE_SIG_S
            );

        assertEq(result, SET_IS_ROOT_RATIFIED_SUCCESS);
        assertTrue(PriceRatifierV1(PRICE_RATIFIER).isRootRatified(ACCOUNT, _root));

        proof[0] = h1;
        proof[1] = right;
        bytes memory ratifierData = abi.encode(_root, uint256(0), proof, ALLOWED_TAKER);
        assertEq(PriceRatifierV1(PRICE_RATIFIER).isRatified(v1Offer(1), ratifierData, ALLOWED_TAKER), CALLBACK_SUCCESS);
    }

    function testFrontendSignatureRateRatifierV1() public {
        bytes32 h0 = HashLib.hashRateRatifierV1Offer(v1Offer(1), 0, ALLOWED_TAKER);
        bytes32 h1 = HashLib.hashRateRatifierV1Offer(v1Offer(2), 0, ALLOWED_TAKER);
        bytes32 h2 = HashLib.hashRateRatifierV1Offer(v1Offer(3), 0, ALLOWED_TAKER);
        bytes32 h3 = HashLib.hashRateRatifierV1Offer(v1Offer(4), 0, ALLOWED_TAKER);
        bytes32 left = HashLib.hashNode(h0, h1);
        bytes32 right = HashLib.hashNode(h2, h3);
        bytes32 _root = HashLib.hashNode(left, right);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = right;
        assertTrue(HashLib.isLeaf(_root, h0, 0, proof));

        proof[0] = h0;
        assertTrue(HashLib.isLeaf(_root, h1, 1, proof));

        proof[0] = h3;
        proof[1] = left;
        assertTrue(HashLib.isLeaf(_root, h2, 2, proof));

        proof[0] = h2;
        assertTrue(HashLib.isLeaf(_root, h3, 3, proof));

        vm.prank(ACCOUNT);
        bytes32 result = RateRatifierV1(RATE_RATIFIER)
            .setIsRootRatifiedWithSig(ACCOUNT, _root, HEIGHT, true, NONCE, DEADLINE, RATE_SIG_V, RATE_SIG_R, RATE_SIG_S);

        assertEq(result, SET_IS_ROOT_RATIFIED_SUCCESS);
        assertTrue(RateRatifierV1(RATE_RATIFIER).isRootRatified(ACCOUNT, _root));

        proof[0] = h1;
        proof[1] = right;
        bytes memory ratifierData = abi.encode(_root, uint256(0), proof, uint256(0), ALLOWED_TAKER);
        assertEq(RateRatifierV1(RATE_RATIFIER).isRatified(v1Offer(1), ratifierData, ALLOWED_TAKER), CALLBACK_SUCCESS);
    }

    // Trick to ensure isRatified checks that the signer is the maker, without having the offers depend on the maker.
    function isAuthorized(address, address signer) external pure returns (bool) {
        return signer == ACCOUNT;
    }
}
