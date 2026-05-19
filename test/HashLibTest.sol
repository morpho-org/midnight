// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {
    HashLib,
    COLLATERAL_PARAMS_TYPEHASH,
    MARKET_TYPEHASH,
    OFFER_TYPEHASH
} from "../src/ratifiers/libraries/HashLib.sol";
import {Market} from "../src/interfaces/IMidnight.sol";

bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
bytes constant MARKET_TYPE =
    "Market(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
bytes constant OFFER_TYPE =
    "Offer(Market market,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxAssets)";

contract HashLibTest is Test {
    function testCollateralParamsTypeHash() public pure {
        assertEq(COLLATERAL_PARAMS_TYPEHASH, keccak256(COLLATERAL_PARAMS_TYPE));
    }

    function testMarketTypeHash() public pure {
        assertEq(MARKET_TYPEHASH, keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)));
    }

    function testOfferTypeHash() public pure {
        assertEq(OFFER_TYPEHASH, keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)));
    }

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

    function testIsLeafSingle(bytes32 x) public pure {
        assertTrue(HashLib.isLeaf(x, x, 0, new bytes32[](0)));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testIsLeafRevertsWhenLeafIndexOutOfRange(bytes32 root, bytes32 leafHash, bytes32 sibling) public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;

        vm.expectRevert(HashLib.LeafIndexOutOfRange.selector);
        HashLib.isLeaf(root, leafHash, 2, proof);
    }

    function testIsLeaf2Leaves(bytes32 x1, bytes32 x2) public pure {
        bytes32 root = keccak256(abi.encode(x1, x2));
        bytes32[] memory proof = new bytes32[](1);

        proof[0] = x2;
        assertTrue(HashLib.isLeaf(root, x1, 0, proof));

        proof[0] = x1;
        assertTrue(HashLib.isLeaf(root, x2, 1, proof));
    }

    function testIsLeaf4Leaves(bytes32 x1, bytes32 x2, bytes32 x3, bytes32 x4) public pure {
        bytes32 leftNode = HashLib.hashNode(x1, x2);
        bytes32 rightNode = HashLib.hashNode(x3, x4);
        bytes32 root = HashLib.hashNode(leftNode, rightNode);

        bytes32[] memory proof = new bytes32[](2);

        proof[0] = x2;
        proof[1] = rightNode;
        assertTrue(HashLib.isLeaf(root, x1, 0, proof));

        proof[0] = x1;
        assertTrue(HashLib.isLeaf(root, x2, 1, proof));

        proof[0] = x4;
        proof[1] = leftNode;
        assertTrue(HashLib.isLeaf(root, x3, 2, proof));

        proof[0] = x3;
        assertTrue(HashLib.isLeaf(root, x4, 3, proof));
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
