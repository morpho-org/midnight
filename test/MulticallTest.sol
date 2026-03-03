// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";

contract MulticallTest is BaseTest {
    function testMulticallSuccess() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(midnight.setFeeSetter, (makeAddr("newFeeSetter")));
        data[1] = abi.encodeCall(midnight.setOwner, (makeAddr("newOwner")));

        vm.prank(midnight.owner());
        midnight.multicall(data);

        assertEq(midnight.owner(), makeAddr("newOwner"), "wrong owner");
        assertEq(midnight.feeSetter(), makeAddr("newFeeSetter"), "wrong fee setter");
    }

    function testMulticallFailing() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(midnight.setOwner, (makeAddr("newOwner")));
        data[1] = abi.encodeCall(midnight.setFeeSetter, (makeAddr("newFeeSetter")));

        vm.prank(midnight.owner());
        vm.expectRevert("only owner");
        midnight.multicall(data);
    }

    function testMulticallEmpty() public {
        midnight.multicall(new bytes[](0));
    }
}
