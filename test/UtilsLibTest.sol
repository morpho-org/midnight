// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, stdError} from "../lib/forge-std/src/Test.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib} from "../src/libraries/TickLib.sol";
import {
    COLLATERAL_PARAMS_TYPE,
    COLLATERAL_PARAMS_TYPEHASH,
    OBLIGATION_TYPE,
    OBLIGATION_TYPEHASH,
    OFFER_TYPE,
    OFFER_TYPEHASH
} from "../src/libraries/ConstantsLib.sol";

contract UtilsLibTest is Test {
    function testFuzzCountBits(uint128 bitmap) public pure {
        uint256 actual = UtilsLib.countBits(bitmap);
        uint256 expected;
        uint128 temp = bitmap;
        while (temp != 0) {
            temp &= temp - 1;
            expected++;
        }
        assertEq(actual, expected);
    }

    function testAtMostOneNonZero(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.atMostOneNonZero(x, y), (x != 0 ? 1 : 0) + (y != 0 ? 1 : 0) <= 1);
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

    /// forge-config: default.allow_internal_expect_revert = true
    function testToUint128Overflow(uint256 x) public {
        x = bound(x, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.expectRevert(UtilsLib.CastOverflow.selector);
        UtilsLib.toUint128(x);
    }

    function mulDivDown(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivDown(x, y, d);
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) external pure {
        UtilsLib.mulDivUp(x, y, d);
    }

    function testWExp() public pure {
        assertApproxEqRel(TickLib.wExp(-20 ether), 0.000000002061153622 ether, 0.001 ether, "exp(-20)");
        assertApproxEqRel(TickLib.wExp(-19 ether), 0.000000005602796438 ether, 0.001 ether, "exp(-19)");
        assertApproxEqRel(TickLib.wExp(-18 ether), 0.000000015229979745 ether, 0.001 ether, "exp(-18)");
        assertApproxEqRel(TickLib.wExp(-17 ether), 0.000000041399377188 ether, 0.001 ether, "exp(-17)");
        assertApproxEqRel(TickLib.wExp(-16 ether), 0.000000112535174719 ether, 0.001 ether, "exp(-16)");
        assertApproxEqRel(TickLib.wExp(-15 ether), 0.000000305902320502 ether, 0.001 ether, "exp(-15)");
        assertApproxEqRel(TickLib.wExp(-14 ether), 0.000000831528719104 ether, 0.001 ether, "exp(-14)");
        assertApproxEqRel(TickLib.wExp(-13 ether), 0.000002260329406981 ether, 0.001 ether, "exp(-13)");
        assertApproxEqRel(TickLib.wExp(-12 ether), 0.000006144212353328 ether, 0.001 ether, "exp(-12)");
        assertApproxEqRel(TickLib.wExp(-11 ether), 0.000016701700790246 ether, 0.001 ether, "exp(-11)");
        assertApproxEqRel(TickLib.wExp(-10 ether), 0.000045399929762485 ether, 0.001 ether, "exp(-10)");
        assertApproxEqRel(TickLib.wExp(-9 ether), 0.00012340980408668 ether, 0.001 ether, "exp(-9)");
        assertApproxEqRel(TickLib.wExp(-8 ether), 0.000335462627902512 ether, 0.001 ether, "exp(-8)");
        assertApproxEqRel(TickLib.wExp(-7 ether), 0.000911881965554516 ether, 0.001 ether, "exp(-7)");
        assertApproxEqRel(TickLib.wExp(-6 ether), 0.002478752176666359 ether, 0.001 ether, "exp(-6)");
        assertApproxEqRel(TickLib.wExp(-5 ether), 0.006737946999085467 ether, 0.001 ether, "exp(-5)");
        assertApproxEqRel(TickLib.wExp(-4 ether), 0.01831563888873418 ether, 0.001 ether, "exp(-4)");
        assertApproxEqRel(TickLib.wExp(-3 ether), 0.049787068367863944 ether, 0.001 ether, "exp(-3)");
        assertApproxEqRel(TickLib.wExp(-2 ether), 0.135335283236612692 ether, 0.001 ether, "exp(-2)");
        assertApproxEqRel(TickLib.wExp(-1 ether), 0.367879441171442322 ether, 0.001 ether, "exp(-1)");
        assertEq(TickLib.wExp(0 ether), 1 ether, "exp(0)");
        assertApproxEqRel(TickLib.wExp(1 ether), 2.718281828459045235 ether, 0.001 ether, "exp(1)");
        assertApproxEqRel(TickLib.wExp(2 ether), 7.389056098930649644 ether, 0.001 ether, "exp(2)");
        assertApproxEqRel(TickLib.wExp(3 ether), 20.085536923187667741 ether, 0.001 ether, "exp(3)");
        assertApproxEqRel(TickLib.wExp(4 ether), 54.59815003314423616 ether, 0.001 ether, "exp(4)");
        assertApproxEqRel(TickLib.wExp(5 ether), 148.413159102576603421 ether, 0.001 ether, "exp(5)");
        assertApproxEqRel(TickLib.wExp(6 ether), 403.428793492735122608 ether, 0.001 ether, "exp(6)");
        assertApproxEqRel(TickLib.wExp(7 ether), 1096.633158428458599264 ether, 0.001 ether, "exp(7)");
        assertApproxEqRel(TickLib.wExp(8 ether), 2980.957987041728274743 ether, 0.001 ether, "exp(8)");
        assertApproxEqRel(TickLib.wExp(9 ether), 8103.083927575384008296 ether, 0.001 ether, "exp(9)");
        assertApproxEqRel(TickLib.wExp(10 ether), 22026.465794806716516958 ether, 0.001 ether, "exp(10)");
        assertApproxEqRel(TickLib.wExp(11 ether), 59874.141715197818455327 ether, 0.001 ether, "exp(11)");
        assertApproxEqRel(TickLib.wExp(12 ether), 162754.791419003920505928 ether, 0.001 ether, "exp(12)");
        assertApproxEqRel(TickLib.wExp(13 ether), 442413.39200892047204928 ether, 0.001 ether, "exp(13)");
        assertApproxEqRel(TickLib.wExp(14 ether), 1202604.284164776777749504 ether, 0.001 ether, "exp(14)");
        assertApproxEqRel(TickLib.wExp(15 ether), 3269017.372472110789246976 ether, 0.001 ether, "exp(15)");
        assertApproxEqRel(TickLib.wExp(16 ether), 8886110.52050787263668224 ether, 0.001 ether, "exp(16)");
        assertApproxEqRel(TickLib.wExp(17 ether), 24154952.75366849249681408 ether, 0.001 ether, "exp(17)");
        assertApproxEqRel(TickLib.wExp(18 ether), 65659969.137330511139838976 ether, 0.001 ether, "exp(18)");
        assertApproxEqRel(TickLib.wExp(19 ether), 178482300.96318726092869632 ether, 0.001 ether, "exp(19)");
        assertApproxEqRel(TickLib.wExp(20 ether), 485165195.409790277969936384 ether, 0.001 ether, "exp(20)");
    }

    function testTypehashes() public pure {
        assertEq(COLLATERAL_PARAMS_TYPEHASH, keccak256(COLLATERAL_PARAMS_TYPE));
        assertEq(OBLIGATION_TYPEHASH, keccak256(bytes.concat(OBLIGATION_TYPE, COLLATERAL_PARAMS_TYPE)));
        assertEq(OFFER_TYPEHASH, keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE)));
    }
}
