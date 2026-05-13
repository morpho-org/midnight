// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {
    HashLib,
    COLLATERAL_PARAMS_TYPE,
    OBLIGATION_TYPE,
    OBLIGATION_TYPEHASH,
    OFFER_TYPE
} from "../src/ratifiers/libraries/HashLib.sol";
import {Obligation} from "../src/interfaces/IMidnight.sol";

contract HashLibTest is Test {
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

    function repeat(string memory str, uint256 n) internal pure returns (string memory) {
        bytes memory result;
        for (uint256 i = 0; i < n; i++) {
            result = bytes.concat(result, bytes(str));
        }
        return string(result);
    }

    function testOfferTreeTypeHashes() public pure {
        for (uint256 height = 0; height <= 20; height++) {
            assertEq(
                HashLib.offerTreeTypeHash(height),
                keccak256(
                    bytes.concat(
                        "OfferTree(Offer",
                        bytes(repeat("[2]", height)),
                        " offerTree)",
                        COLLATERAL_PARAMS_TYPE,
                        OBLIGATION_TYPE,
                        OFFER_TYPE
                    )
                )
            );
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testOfferTreeTypeHashInvalidHeight(uint256 height) public {
        height = bound(height, 21, type(uint256).max);
        vm.expectRevert(HashLib.TreeTooHigh.selector);
        HashLib.offerTreeTypeHash(height);
    }
}
