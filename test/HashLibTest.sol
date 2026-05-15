// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {
    HashLib,
    COLLATERAL_PARAMS_TYPE,
    MARKET_TYPE,
    MARKET_TYPEHASH,
    OFFER_TYPE
} from "../src/ratifiers/libraries/HashLib.sol";
import {Market} from "../src/interfaces/IMidnight.sol";

contract HashLibTest is Test {
    function testHashMarketMatchesReference(Market memory market) public pure {
        bytes32[] memory collateralParamsHashes = new bytes32[](market.collateralParams.length);
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            collateralParamsHashes[i] = HashLib.hashCollateralParams(market.collateralParams[i]);
        }
        bytes32 expectedHash = keccak256(
            abi.encode(
                MARKET_TYPEHASH,
                market.loanToken,
                keccak256(abi.encodePacked(collateralParamsHashes)),
                market.maturity,
                market.rcfThreshold,
                market.enterGate,
                market.liquidatorGate
            )
        );
        assertEq(HashLib.hashMarket(market), expectedHash);
    }

    function testIsLeafPreservesSiblingOrder() public pure {
        bytes32 leftLeaf = bytes32(uint256(2));
        bytes32 rightLeaf = bytes32(uint256(1));
        bytes32 orderedRoot = HashLib.orderedHash(leftLeaf, rightLeaf);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leftLeaf;

        assertTrue(HashLib.isLeaf(orderedRoot, rightLeaf, proof, 1));
        assertFalse(HashLib.isLeaf(orderedRoot, rightLeaf, proof, 0));
    }

    function testIsLeaf4Leaves() public pure {
        bytes32 leaf0 = bytes32(uint256(1));
        bytes32 leaf1 = bytes32(uint256(2));
        bytes32 leaf2 = bytes32(uint256(3));
        bytes32 leaf3 = bytes32(uint256(4));
        bytes32 leftNode = HashLib.orderedHash(leaf0, leaf1);
        bytes32 rightNode = HashLib.orderedHash(leaf2, leaf3);
        bytes32 orderedRoot = HashLib.orderedHash(leftNode, rightNode);

        bytes32[] memory proof = new bytes32[](2);

        proof[0] = leaf1;
        proof[1] = rightNode;
        assertTrue(HashLib.isLeaf(orderedRoot, leaf0, proof, 0));

        proof[0] = leaf0;
        assertTrue(HashLib.isLeaf(orderedRoot, leaf1, proof, 1));

        proof[0] = leaf3;
        proof[1] = leftNode;
        assertTrue(HashLib.isLeaf(orderedRoot, leaf2, proof, 2));

        proof[0] = leaf2;
        assertTrue(HashLib.isLeaf(orderedRoot, leaf3, proof, 3));
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
                        MARKET_TYPE,
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
