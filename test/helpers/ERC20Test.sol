// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

contract ERC20Test is Test {
    ERC20 internal erc20;

    function setUp() public {
        erc20 = new ERC20("ERC20Test", "ERC20T");
    }

    function testApprove(address spender, uint256 amount) public {
        vm.assume(amount > 0);
        erc20.approve(spender, amount);
        assertEq(erc20.allowance(address(this), spender), amount);
    }

    function testTransfer(address recipient, uint256 amount) public {
        vm.assume(amount > 0);
        deal(address(erc20), address(this), amount);
        erc20.transfer(recipient, amount);
        assertEq(erc20.balanceOf(recipient), amount);

        if (recipient != address(this)) {
            assertEq(erc20.balanceOf(address(this)), 0);
        }
    }

    function testTransferFrom(address sender, address recipient, uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(sender != recipient);
        deal(address(erc20), sender, amount);
        vm.prank(sender);
        erc20.approve(address(this), amount);
        erc20.transferFrom(sender, recipient, amount);
        assertEq(erc20.balanceOf(recipient), amount);
        if (sender != recipient) {
            assertEq(erc20.balanceOf(sender), 0);
        }
        assertEq(erc20.allowance(sender, address(this)), 0);
    }

    function testTransferInsufficientBalance(address recipient, uint256 amount) public {
        vm.assume(amount > 0);
        vm.expectRevert("Insufficient balance");
        erc20.transfer(recipient, amount);
    }

    function testTransferFromInsufficientBalance(address sender, address recipient, uint256 amount) public {
        vm.assume(amount > 0);
        vm.prank(sender);
        erc20.approve(address(this), amount);
        vm.expectRevert("Insufficient balance");
        erc20.transferFrom(sender, recipient, amount);
    }

    function testTransferFromInsufficientAllowance(address sender, address recipient, uint256 amount) public {
        vm.assume(amount > 0);
        deal(address(erc20), sender, amount);
        vm.expectRevert("Insufficient allowance");
        erc20.transferFrom(sender, recipient, amount);
    }
}
