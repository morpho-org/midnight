// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback.sol";
import {BlueBuyCallbackFactory} from "../src/periphery/BlueBuyCallbackFactory.sol";
import {BlueMarketParams, IBlue} from "../src/periphery/interfaces/IBlue.sol";
import {IBlueBuyCallbackFactory} from "../src/periphery/interfaces/IBlueBuyCallbackFactory.sol";

contract BlueBuyCallbackFactoryTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal owner = makeAddr("owner");
    address internal otherOwner = makeAddr("otherOwner");
    MockFactoryBlue internal blue;
    BlueBuyCallbackFactory internal factory;

    function setUp() public {
        blue = new MockFactoryBlue();
        factory = new BlueBuyCallbackFactory(midnight, address(blue));
    }

    function testConstructor() public view {
        assertEq(factory.MIDNIGHT(), midnight);
        assertEq(factory.BLUE(), address(blue));
    }

    function testCreateBlueBuyCallback() public {
        vm.prank(owner);
        factory.createBlueBuyCallback();
        address callbackAddress = factory.callbackOf(owner);
        BlueBuyCallback callback = BlueBuyCallback(callbackAddress);

        assertEq(factory.callbackOf(owner), callbackAddress);
        assertEq(callback.OWNER(), owner);
        assertEq(callback.MIDNIGHT(), midnight);
        assertEq(callback.BLUE(), address(blue));
        assertTrue(blue.isAuthorized(callbackAddress, owner));
    }

    function testCreateBlueBuyCallbackEmitsEvent() public {
        vm.recordLogs();
        vm.prank(owner);
        factory.createBlueBuyCallback();
        address callback = factory.callbackOf(owner);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], IBlueBuyCallbackFactory.CreateBlueBuyCallback.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(owner))));
        assertEq(abi.decode(logs[0].data, (address)), callback);
    }

    function testCreateBlueBuyCallbackRevertsIfAlreadyCreated() public {
        vm.startPrank(owner);
        factory.createBlueBuyCallback();

        vm.expectRevert(IBlueBuyCallbackFactory.AlreadyCreated.selector);
        factory.createBlueBuyCallback();
        vm.stopPrank();
    }

    function testCreateBlueBuyCallbackDifferentOwners() public {
        vm.prank(owner);
        factory.createBlueBuyCallback();
        vm.prank(otherOwner);
        factory.createBlueBuyCallback();

        address callback = factory.callbackOf(owner);
        address otherCallback = factory.callbackOf(otherOwner);

        assertTrue(callback != otherCallback);
        assertEq(factory.callbackOf(owner), callback);
        assertEq(factory.callbackOf(otherOwner), otherCallback);
    }
}

contract MockFactoryBlue is IBlue {
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
    }

    function withdraw(BlueMarketParams memory, uint256, uint256, address, address)
        external
        pure
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}
