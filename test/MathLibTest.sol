// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/libraries/MathLib.sol";

contract MathLibTest is Test {
    function testMulDivDown(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        if (x > 0) y = bound(y, 0, type(uint256).max / x);

        assertEq(MathLib.mulDivDown(x, y, d), (x * y) / d, "mulDivDown result mismatch");
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

        assertEq(MathLib.mulDivUp(x, y, d), (x * y + (d - 1)) / d, "mulDivUp result mismatch");
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

    function mulDivDown(uint256 x, uint256 y, uint256 d) external pure {
        MathLib.mulDivDown(x, y, d);
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) external pure {
        MathLib.mulDivUp(x, y, d);
    }
}
