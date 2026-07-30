// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback.sol";
import {BlueBuyCallbackFactory} from "../src/periphery/BlueBuyCallbackFactory.sol";
import {IBlueBuyCallbackFactory} from "../src/periphery/interfaces/IBlueBuyCallbackFactory.sol";

contract BlueBuyCallbackFactoryTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal owner = makeAddr("owner");
    IMorpho internal blue;
    BlueBuyCallbackFactory internal factory;

    function setUp() public {
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        factory = new BlueBuyCallbackFactory(midnight, address(blue));
    }

    function testConstructor() public view {
        assertEq(factory.MIDNIGHT(), midnight);
        assertEq(factory.BLUE(), address(blue));
    }

    function testCreateBlueBuyCallback(bytes32 salt) public {
        vm.prank(owner);
        address callbackAddress = factory.createBlueBuyCallback(owner, salt);
        BlueBuyCallback callback = BlueBuyCallback(callbackAddress);
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(BlueBuyCallback).creationCode, abi.encode(owner, midnight, address(blue))));

        assertEq(callbackAddress, vm.computeCreate2Address(salt, initCodeHash, address(factory)));
        assertEq(factory.callbackOf(owner, salt), callbackAddress);
        assertEq(callback.OWNER(), owner);
        assertEq(callback.MIDNIGHT(), midnight);
        assertEq(callback.BLUE(), address(blue));
        assertTrue(factory.isBlueCallback(callbackAddress));
        assertTrue(blue.isAuthorized(callbackAddress, owner));
    }

    function testCreateBlueBuyCallbackEmitsEvent(bytes32 salt) public {
        vm.recordLogs();
        vm.prank(owner);
        factory.createBlueBuyCallback(owner, salt);
        address callback = factory.callbackOf(owner, salt);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[1].emitter, address(factory));
        assertEq(logs[1].topics[0], IBlueBuyCallbackFactory.CreateBlueBuyCallback.selector);
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(owner))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(owner))));
        (bytes32 emittedSalt, address emittedCallback) = abi.decode(logs[1].data, (bytes32, address));
        assertEq(emittedSalt, salt);
        assertEq(emittedCallback, callback);
    }

    function testCreateBlueBuyCallbackIsIdempotent(bytes32 salt) public {
        vm.prank(owner);
        address callback = factory.createBlueBuyCallback(owner, salt);

        vm.prank(owner);
        address callbackAgain = factory.createBlueBuyCallback(owner, salt);

        assertEq(callbackAgain, callback);
        assertEq(factory.callbackOf(owner, salt), callback);
    }

    function testCreateMultipleBlueBuyCallbacksPerOwner(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        vm.startPrank(owner);
        address callback1 = factory.createBlueBuyCallback(owner, salt1);
        address callback2 = factory.createBlueBuyCallback(owner, salt2);
        vm.stopPrank();

        assertTrue(callback1 != callback2);
        assertEq(factory.callbackOf(owner, salt1), callback1);
        assertEq(factory.callbackOf(owner, salt2), callback2);
        assertTrue(factory.isBlueCallback(callback1));
        assertTrue(factory.isBlueCallback(callback2));
    }

    function testCreateBlueBuyCallbackForOtherOwner(bytes32 salt) public {
        address caller = makeAddr("caller");

        vm.prank(caller);
        factory.createBlueBuyCallback(owner, salt);

        address callback = factory.callbackOf(owner, salt);
        assertEq(BlueBuyCallback(callback).OWNER(), owner);
        assertTrue(blue.isAuthorized(callback, owner));
    }

    function testIsBlueCallbackFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isBlueCallback(account));
    }
}
