// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {BlueSwapBuyCallback} from "../src/periphery/blue-swap-buy-callback/BlueSwapBuyCallback.sol";
import {BlueSwapBuyCallbackFactory} from "../src/periphery/blue-swap-buy-callback/BlueSwapBuyCallbackFactory.sol";
import {
    IBlueSwapBuyCallbackFactory
} from "../src/periphery/blue-swap-buy-callback/interfaces/IBlueSwapBuyCallbackFactory.sol";

contract BlueSwapBuyCallbackFactoryTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal owner = makeAddr("owner");
    IMorpho internal blue;
    BlueSwapBuyCallbackFactory internal factory;

    function setUp() public {
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        factory = new BlueSwapBuyCallbackFactory(midnight, address(blue));
    }

    function testConstructor() public view {
        assertEq(factory.MIDNIGHT(), midnight);
        assertEq(factory.BLUE(), address(blue));
    }

    function testCreateBlueSwapBuyCallback(bytes32 salt) public {
        vm.prank(owner);
        address callbackAddress = factory.createBlueSwapBuyCallback(owner, salt);
        BlueSwapBuyCallback callback = BlueSwapBuyCallback(callbackAddress);
        // forge-lint: disable-next-item(encode-packed-collision)
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(BlueSwapBuyCallback).creationCode, abi.encode(owner, midnight, address(blue)))
        );

        assertEq(callbackAddress, vm.computeCreate2Address(salt, initCodeHash, address(factory)));
        assertEq(factory.callbackOf(owner, salt), callbackAddress);
        assertEq(callback.OWNER(), owner);
        assertEq(callback.MIDNIGHT(), midnight);
        assertEq(callback.BLUE(), address(blue));
        assertTrue(factory.isBlueSwapBuyCallback(callbackAddress));
        assertTrue(blue.isAuthorized(callbackAddress, owner));
    }

    function testCreateBlueSwapBuyCallbackEmitsEvent(bytes32 salt) public {
        vm.recordLogs();
        vm.prank(owner);
        factory.createBlueSwapBuyCallback(owner, salt);
        address callback = factory.callbackOf(owner, salt);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[1].emitter, address(factory));
        assertEq(logs[1].topics[0], IBlueSwapBuyCallbackFactory.CreateBlueSwapBuyCallback.selector);
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(owner))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(owner))));
        (bytes32 emittedSalt, address emittedCallback) = abi.decode(logs[1].data, (bytes32, address));
        assertEq(emittedSalt, salt);
        assertEq(emittedCallback, callback);
    }

    function testCreateBlueSwapBuyCallbackIsIdempotent(bytes32 salt) public {
        vm.prank(owner);
        address callback = factory.createBlueSwapBuyCallback(owner, salt);

        vm.prank(owner);
        address callbackAgain = factory.createBlueSwapBuyCallback(owner, salt);

        assertEq(callbackAgain, callback);
        assertEq(factory.callbackOf(owner, salt), callback);
    }

    function testCreateMultipleBlueSwapBuyCallbacksPerOwner(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        vm.startPrank(owner);
        address callback1 = factory.createBlueSwapBuyCallback(owner, salt1);
        address callback2 = factory.createBlueSwapBuyCallback(owner, salt2);
        vm.stopPrank();

        assertTrue(callback1 != callback2);
        assertEq(factory.callbackOf(owner, salt1), callback1);
        assertEq(factory.callbackOf(owner, salt2), callback2);
        assertTrue(factory.isBlueSwapBuyCallback(callback1));
        assertTrue(factory.isBlueSwapBuyCallback(callback2));
    }

    function testCreateBlueSwapBuyCallbackForOtherOwner(bytes32 salt) public {
        address caller = makeAddr("caller");

        vm.prank(caller);
        factory.createBlueSwapBuyCallback(owner, salt);

        address callback = factory.callbackOf(owner, salt);
        assertEq(BlueSwapBuyCallback(callback).OWNER(), owner);
        assertTrue(blue.isAuthorized(callback, owner));
    }

    function testIsBlueSwapBuyCallbackFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isBlueSwapBuyCallback(account));
    }
}
