// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {BlueFallbackRollingFactory} from "../src/periphery/blue-fallback-rolling/BlueFallbackRollingFactory.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {IBlueFallbackRollingFactory} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRollingFactory.sol";

contract BlueFallbackRollingFactoryTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal blue = makeAddr("blue");
    address internal caller = makeAddr("caller");
    BlueFallbackRollingFactory internal factory;

    function setUp() public {
        factory = new BlueFallbackRollingFactory(midnight, blue);
    }

    function testConstructor() public view {
        assertEq(factory.MIDNIGHT(), midnight);
        assertEq(factory.BLUE(), blue);
    }

    function testCreateBlueFallbackRolling(bytes32 midnightId, bytes32 blueId, uint64 start, uint64 incentive) public {
        incentive = uint64(bound(incentive, 0, WAD));

        vm.prank(caller);
        address rollingAddress = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);
        BlueFallbackRolling rolling = BlueFallbackRolling(rollingAddress);
        bytes32 configId = keccak256(abi.encode(midnightId, blueId, start, incentive));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(BlueFallbackRolling).creationCode, abi.encode(midnight, blue, midnightId, blueId, start, incentive)
            )
        );

        assertEq(rollingAddress, vm.computeCreate2Address(configId, initCodeHash, address(factory)));
        assertEq(factory.blueFallbackRollingOf(configId), rollingAddress);
        assertTrue(factory.isBlueFallbackRolling(rollingAddress));
        assertEq(rolling.MIDNIGHT(), midnight);
        assertEq(rolling.BLUE(), blue);
        assertEq(rolling.MIDNIGHT_ID(), midnightId);
        assertEq(rolling.BLUE_ID(), blueId);
        assertEq(rolling.START(), start);
        assertEq(rolling.INCENTIVE(), incentive);
    }

    function testCreateBlueFallbackRollingEmitsEvent(bytes32 midnightId, bytes32 blueId, uint64 start, uint64 incentive)
        public
    {
        incentive = uint64(bound(incentive, 0, WAD));

        vm.recordLogs();
        vm.prank(caller);
        address rolling = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics[0], IBlueFallbackRollingFactory.CreateBlueFallbackRolling.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(caller))));
        assertEq(logs[0].topics[2], midnightId);
        assertEq(logs[0].topics[3], blueId);
        (uint64 emittedStart, uint64 emittedIncentive, address emittedRolling) =
            abi.decode(logs[0].data, (uint64, uint64, address));
        assertEq(emittedStart, start);
        assertEq(emittedIncentive, incentive);
        assertEq(emittedRolling, rolling);
    }

    function testCreateBlueFallbackRollingIsIdempotent(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 incentive
    ) public {
        incentive = uint64(bound(incentive, 0, WAD));

        address rolling = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);
        address rollingAgain = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);

        assertEq(rollingAgain, rolling);
        assertEq(factory.blueFallbackRollingOf(keccak256(abi.encode(midnightId, blueId, start, incentive))), rolling);
    }

    function testCreateBlueFallbackRollingForDifferentConfigs(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 incentive
    ) public {
        incentive = uint64(bound(incentive, 0, WAD - 1));
        start = uint64(bound(start, 0, type(uint64).max - 1));

        address rolling = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);
        address otherStartRolling = factory.createBlueFallbackRolling(midnightId, blueId, start + 1, incentive);
        address otherIncentiveRolling = factory.createBlueFallbackRolling(midnightId, blueId, start, incentive + 1);

        assertTrue(rolling != otherStartRolling);
        assertTrue(rolling != otherIncentiveRolling);
        assertTrue(otherStartRolling != otherIncentiveRolling);
        assertTrue(factory.isBlueFallbackRolling(rolling));
        assertTrue(factory.isBlueFallbackRolling(otherStartRolling));
        assertTrue(factory.isBlueFallbackRolling(otherIncentiveRolling));
    }

    function testCreateBlueFallbackRollingRevertsForTooLargeIncentive(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 incentive
    ) public {
        incentive = uint64(bound(incentive, WAD + 1, type(uint64).max));

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        factory.createBlueFallbackRolling(midnightId, blueId, start, incentive);
    }

    function testIsBlueFallbackRollingFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isBlueFallbackRolling(account));
    }
}
