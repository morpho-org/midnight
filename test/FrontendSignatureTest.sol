// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Midnight} from "../src/Midnight.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {Offer} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/interfaces/IEcrecover.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

// Paste from frontend output.
address constant ACCOUNT = address(0); // TODO: paste wallet address
uint8 constant SIG_V = 0; // TODO: paste v
bytes32 constant SIG_R = bytes32(0); // TODO: paste r
bytes32 constant SIG_S = bytes32(0); // TODO: paste s

address constant RATIFIER = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
uint256 constant HEIGHT = 2;

contract FrontendSignatureTest is Test {
    Midnight internal midnight;

    function setUp() public {
        midnight = new Midnight();

        EcrecoverRatifier impl = new EcrecoverRatifier(address(midnight));
        vm.etch(RATIFIER, address(impl).code);

        vm.prank(ACCOUNT);
        midnight.setIsAuthorized(ACCOUNT, RATIFIER, true);
    }

    function defaultOffer(uint8 number) internal pure returns (Offer memory offer) {
        offer.obligation.loanToken = address(uint160(0x1111111111111111111111111111111111111111) * uint160(number));
        offer.buy = true;
        offer.maker = ACCOUNT;
        offer.expiry = 1 + 3600; // block.timestamp defaults to 1 in forge
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

    function testFrontendSignatureVerification() public {
        Offer[4] memory offers;
        offers[0] = defaultOffer(1);
        offers[1] = defaultOffer(2);
        offers[2] = defaultOffer(3);
        offers[3] = defaultOffer(4);

        offers = sortOffers(offers);

        bytes32 h0 = UtilsLib.hashOffer(offers[0]);
        bytes32 h1 = UtilsLib.hashOffer(offers[1]);
        bytes32 h2 = UtilsLib.hashOffer(offers[2]);
        bytes32 h3 = UtilsLib.hashOffer(offers[3]);
        bytes32 left = UtilsLib.commutativeHash(h0, h1);
        bytes32 right = UtilsLib.commutativeHash(h2, h3);
        bytes32 _root = UtilsLib.commutativeHash(left, right);

        bytes memory ratifierData = abi.encode(Signature({v: SIG_V, r: SIG_R, s: SIG_S}), HEIGHT);

        // Proof for offers[0]: sibling hash, then uncle subtree hash.
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = right;

        address taker = makeAddr("taker");
        vm.prank(taker);
        midnight.take(0, taker, address(0), hex"", taker, offers[0], ratifierData, _root, proof);
    }
}
