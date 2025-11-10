// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
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

    function testMax(uint256 a, uint256 b) public pure {
        assertEq(UtilsLib.max(a, b), a > b ? a : b);
    }
}
