// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(morphoV2.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        morphoV2.setOwner(rdm);
        assertEq(morphoV2.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setOwner(makeAddr("newOwner"));
    }

    function testSetObligationCreatorSuccess(address obligationCreator) public {
        morphoV2.setObligationCreator(obligationCreator);
        assertEq(morphoV2.obligationCreator(), obligationCreator);
    }

    function testSetObligationCreatorOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setObligationCreator(makeAddr("newObligationCreator"));
    }

    function testCreateObligationSuccess(bytes32 id) public {
        morphoV2.createObligation(id);
        assertEq(morphoV2.isObligation(id), true);
    }

    function testCreateObligationOnlyObligationCreator(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only obligationCreator");
        morphoV2.createObligation(id);
    }
}
