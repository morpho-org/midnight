// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, stdError} from "../lib/forge-std/src/Test.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract UtilsLibTest is Test {
    function testAtMostOneNonZero(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.atMostOneNonZero(x, y), (x != 0 ? 1 : 0) + (y != 0 ? 1 : 0) <= 1);
    }

    function testAtMostOneNonZero(uint256 a, uint256 b, uint256 c, uint256 d) public pure {
        assertEq(
            UtilsLib.atMostOneNonZero(a, b, c, d),
            (a != 0 ? 1 : 0) + (b != 0 ? 1 : 0) + (c != 0 ? 1 : 0) + (d != 0 ? 1 : 0) <= 1
        );
    }

    function testMin(uint256 a, uint256 b) public pure {
        assertEq(UtilsLib.min(a, b), a < b ? a : b);
    }

    function testZeroFloorSub(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.zeroFloorSub(x, y), x > y ? x - y : 0);
    }

    function testMulDivDown(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        if (x > 0) y = bound(y, 0, type(uint256).max / x);

        assertEq(UtilsLib.mulDivDown(x, y, d), (x * y) / d, "mulDivDown result mismatch");
    }

    function testMulDivDownDivisionByZero(uint256 x, uint256 y) public {
        if (x > 0) y = bound(y, 0, type(uint256).max / x);

        vm.expectRevert(stdError.divisionError);
        this.mulDivDown(x, y, 0);
    }

    function testMulDivDownOverflow(uint256 x, uint256 y, uint256 d) public {
        x = bound(x, 2, type(uint256).max);
        y = bound(y, type(uint256).max / x + 1, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        this.mulDivDown(x, y, d);
    }

    function testMulDivUp(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        if (x > 0) y = bound(y, 0, (type(uint256).max - (d - 1)) / x);

        assertEq(UtilsLib.mulDivUp(x, y, d), (x * y + (d - 1)) / d, "mulDivUp result mismatch");
    }

    function testMulDivUpDivisionByZero(uint256 x, uint256 y) public {
        // because there is d-1.
        vm.expectRevert(stdError.arithmeticError);
        this.mulDivUp(x, y, 0);
    }

    function testMulDivUpOverflow(uint256 x, uint256 y, uint256 d) public {
        d = bound(d, 1, type(uint256).max);
        x = bound(x, 1, type(uint256).max);
        vm.assume(!(d == 1 && x == 1)); // covered by testMulDivUp.
        y = bound(y, (type(uint256).max - (d - 1)) / x + 1, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        this.mulDivUp(x, y, d);
    }

    function testIsLeafSingle(bytes32 x) public pure {
        assertTrue(UtilsLib.isLeaf(x, x, new bytes32[](0)));
    }

    function testIsLeaf2Leaves(bytes32 x, bytes32 y) public pure {
        bytes32 root = keccak256(x < y ? abi.encode(x, y) : abi.encode(y, x));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = y;
        assertTrue(UtilsLib.isLeaf(root, x, proof));
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
        assertTrue(UtilsLib.isLeaf(root, x, proof));
    }

    function mulDivDown(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivDown(x, y, d);
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivUp(x, y, d);
    }
}
