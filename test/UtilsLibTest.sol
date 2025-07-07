// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/libraries/UtilsLib.sol";

contract UtilsLibTest is Test {
    function testExactlyOneZero(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.exactlyOneZero(x, y), (x == 0) != (y == 0), "exactlyOneZero result mismatch");
    }

    function testMin(uint256 x, uint256 y) public pure {
        assertEq(UtilsLib.min(x, y), x < y ? x : y, "min result mismatch");
    }
}
