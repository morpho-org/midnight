// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";

contract MulticallTest is BaseTest {
    function testMulticallSuccess() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(morphoV2.setFeeSetter, (makeAddr("newFeeSetter")));
        data[1] = abi.encodeCall(morphoV2.setOwner, (makeAddr("newOwner")));

        vm.prank(morphoV2.owner());
        morphoV2.multicall(data);

        assertEq(morphoV2.owner(), makeAddr("newOwner"), "wrong owner");
        assertEq(morphoV2.feeSetter(), makeAddr("newFeeSetter"), "wrong fee setter");
    }

    function testMulticallFailing() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(morphoV2.setOwner, (makeAddr("newOwner")));
        data[1] = abi.encodeCall(morphoV2.setFeeSetter, (makeAddr("newFeeSetter")));

        vm.prank(morphoV2.owner());
        vm.expectRevert("Only owner");
        morphoV2.multicall(data);
    }

    function testMulticallEmpty() public {
        morphoV2.multicall(new bytes[](0));
    }
}
