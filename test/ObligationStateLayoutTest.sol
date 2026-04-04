// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ObligationState} from "../src/interfaces/IMidnight.sol";

contract ObligationStateHarness {
    mapping(bytes32 id => ObligationState) public obligationState;

    function setCreated(bytes32 id, bool created) external {
        obligationState[id].created = created;
    }

    function setFee(bytes32 id, uint256 index, uint16 fee) external {
        obligationState[id].fees[index] = fee;
    }

    function setContinuousFee(bytes32 id, uint32 continuousFee) external {
        obligationState[id].continuousFee = continuousFee;
    }
}

contract ObligationStateLayoutTest is Test {
    ObligationStateHarness internal harness;

    bytes32 internal constant ID = keccak256("obligation-id");
    uint256 internal constant OBLIGATION_STATE_MAPPING_SLOT = 0;

    function setUp() public {
        harness = new ObligationStateHarness();
    }

    function testCreatedUsesItsOwnSlot() public {
        bytes32 baseSlot = keccak256(abi.encode(ID, OBLIGATION_STATE_MAPPING_SLOT));

        harness.setCreated(ID, true);

        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 0))), 0, "slot 0");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 1))), 0, "slot 1");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 2))), 1, "created");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 3))), 0, "fees");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 4))), 0, "continuousFee");
    }

    function testFeesAndContinuousFeeUseLaterSlots() public {
        bytes32 baseSlot = keccak256(abi.encode(ID, OBLIGATION_STATE_MAPPING_SLOT));

        harness.setFee(ID, 0, 1);
        harness.setContinuousFee(ID, 1);

        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 2))), 0, "created");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 3))), 1, "fees");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 4))), 1, "continuousFee");
    }
}
