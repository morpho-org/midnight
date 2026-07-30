// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback/BlueBuyCallback.sol";
import {BlueBuyCallbackFactory} from "../src/periphery/BlueBuyCallback/BlueBuyCallbackFactory.sol";
import {IBlueBuyCallbackFactory} from "../src/periphery/BlueBuyCallback/interfaces/IBlueBuyCallbackFactory.sol";

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

    function testCreateBlueBuyCallback() public {
        vm.prank(owner);
        address callbackAddress = factory.createBlueBuyCallback(owner);
        BlueBuyCallback callback = BlueBuyCallback(callbackAddress);
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(BlueBuyCallback).creationCode, abi.encode(owner, midnight, address(blue))));

        assertEq(callbackAddress, vm.computeCreate2Address(bytes32(0), initCodeHash, address(factory)));
        assertEq(factory.callbackOf(owner), callbackAddress);
        assertEq(callback.OWNER(), owner);
        assertEq(callback.MIDNIGHT(), midnight);
        assertEq(callback.BLUE(), address(blue));
        assertTrue(factory.isBlueCallback(callbackAddress));
        assertTrue(blue.isAuthorized(callbackAddress, owner));
    }

    function testCreateBlueBuyCallbackEmitsEvent() public {
        vm.recordLogs();
        vm.prank(owner);
        factory.createBlueBuyCallback(owner);
        address callback = factory.callbackOf(owner);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[1].emitter, address(factory));
        assertEq(logs[1].topics[0], IBlueBuyCallbackFactory.CreateBlueBuyCallback.selector);
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(owner))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(owner))));
        assertEq(abi.decode(logs[1].data, (address)), callback);
    }

    function testCreateBlueBuyCallbackRevertsIfAlreadyDeployed() public {
        vm.startPrank(owner);
        factory.createBlueBuyCallback(owner);

        vm.expectRevert();
        factory.createBlueBuyCallback(owner);
        vm.stopPrank();
    }

    function testCreateBlueBuyCallbackForOtherOwner() public {
        address caller = makeAddr("caller");

        vm.prank(caller);
        factory.createBlueBuyCallback(owner);

        address callback = factory.callbackOf(owner);
        assertEq(BlueBuyCallback(callback).OWNER(), owner);
        assertTrue(blue.isAuthorized(callback, owner));
    }

    function testIsBlueCallbackFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isBlueCallback(account));
    }
}
