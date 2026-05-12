// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {HashLib, OBLIGATION_TYPEHASH, OFFER_TYPEHASH} from "../src/ratifiers/HashLib.sol";
import {Offer, Obligation} from "../src/interfaces/IMidnight.sol";

contract HashLibTest is Test {
    function testHashOfferMatchesReference(Offer memory offer) public pure {
        /// Equivalent to HashLib.hashOffer but does not compile under Certora's mode (stack-too-deep).
        bytes32 expectedHash = keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                HashLib.hashObligation(offer.obligation),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                offer.tick,
                offer.group,
                offer.session,
                offer.callback,
                keccak256(offer.callbackData),
                offer.receiverIfMakerIsSeller,
                offer.ratifier,
                offer.reduceOnly,
                offer.maxUnits,
                offer.maxSellerAssets,
                offer.maxBuyerAssets
            )
        );
        assertEq(HashLib.hashOffer(offer), expectedHash);
    }

    function testHashObligationMatchesReference(Obligation memory obligation) public pure {
        bytes32[] memory collateralParamsHashes = new bytes32[](obligation.collateralParams.length);
        for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
            collateralParamsHashes[i] = HashLib.hashCollateralParams(obligation.collateralParams[i]);
        }
        bytes32 expectedHash = keccak256(
            abi.encode(
                OBLIGATION_TYPEHASH,
                obligation.loanToken,
                keccak256(abi.encodePacked(collateralParamsHashes)),
                obligation.maturity,
                obligation.rcfThreshold,
                obligation.enterGate,
                obligation.liquidatorGate
            )
        );
        assertEq(HashLib.hashObligation(obligation), expectedHash);
    }

    function testIsLeafSingle(bytes32 x) public pure {
        assertTrue(HashLib.isLeaf(x, x, new bytes32[](0)));
    }

    function testIsLeaf2Leaves(bytes32 x, bytes32 y) public pure {
        bytes32 root = keccak256(x < y ? abi.encode(x, y) : abi.encode(y, x));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = y;
        assertTrue(HashLib.isLeaf(root, x, proof));
    }

    function testIsLeaf4Leaves(bytes32 x, bytes32 y, bytes32 z, bytes32 w) public pure {
        x = bytes32(bound(uint256(x), 0, type(uint256).max - 3));
        y = bytes32(bound(uint256(y), uint256(x), type(uint256).max - 2));
        z = bytes32(bound(uint256(z), uint256(y), type(uint256).max - 1));
        w = bytes32(bound(uint256(w), uint256(z), type(uint256).max));
        bytes32 leftNode = keccak256(x < y ? abi.encode(x, y) : abi.encode(y, x));
        bytes32 rightNode = keccak256(z < w ? abi.encode(z, w) : abi.encode(w, z));
        bytes32 root =
            keccak256(leftNode < rightNode ? abi.encode(leftNode, rightNode) : abi.encode(rightNode, leftNode));
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = y;
        proof[1] = rightNode;
        assertTrue(HashLib.isLeaf(root, x, proof));
    }
}
