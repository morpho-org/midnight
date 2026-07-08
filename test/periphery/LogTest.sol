// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.13;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Log, MAX_DATA_LENGTH} from "../../src/periphery/Log.sol";

contract LogTest is Test {
    address public _log;

    function setUp() public {
        _log = address(new Log());
    }

    function testLog(bytes memory data) public {
        vm.assume(data.length % 32 == 0);
        vm.assume(data.length == 32);
        vm.expectEmitAnonymous();
        emit Log.Data(data);
        (bool success, bytes memory result) = _log.call(data);
        console.logString(string(result));
        assertTrue(success, "Log failed");
        assertEq(result, hex"");
    }

    function testMaxDataLength() public pure {
        assertEq(MAX_DATA_LENGTH, 1_000_000);
    }

    function testRevertsWhenDataTooLong() public {
        bytes memory data = new bytes(MAX_DATA_LENGTH + 1);
        (bool success, bytes memory result) = _log.call(data);
        assertFalse(success, "Log succeeded");
        assertEq(result, abi.encodeWithSelector(Log.DataTooLong.selector));
    }

    /// forge-config: default.isolate = true
    function testGasLog1WordZeros() public {
        bytes memory data = new bytes(32);
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }

    /// forge-config: default.isolate = true
    function testGasLog1Word() public {
        bytes memory data;
        unchecked {
            data = abi.encode(0 - 1);
        }
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }

    /// forge-config: default.isolate = true
    function testGasLog10WordsZeros() public {
        bytes memory data = new bytes(10 * 32);
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }

    /// forge-config: default.isolate = true
    function testGasLog10Words() public {
        bytes memory data;
        unchecked {
            for (uint256 i = 0; i < 10; i++) {
                data = abi.encode(data, 0 - 1);
            }
        }
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }

    /// forge-config: default.isolate = true
    function testGasLog100WordsZeros() public {
        bytes memory data = new bytes(100 * 32);
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }

    /// forge-config: default.isolate = true
    function testGasLog100Words() public {
        bytes memory data;
        unchecked {
            for (uint256 i = 0; i < 100; i++) {
                data = abi.encode(data, 0 - 1);
            }
        }
        uint256 gasBefore = gasleft();
        (bool success,) = _log.call(data);
        console.log("gas", gasBefore - gasleft());
        assertTrue(success, "Log failed");
    }
}
