// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";

contract FlashLoanTest is BaseTest, IFlashLoanCallback {
    uint256 internal amountStored;
    bytes internal dataStored;
    bool internal discardToken = false;

    function testFlashLoan(uint256 amount, bytes memory data) public {
        amount = bound(amount, 1, type(uint256).max);
        amountStored = amount;
        dataStored = data;

        deal(address(loanToken), address(midnight), amount);
        midnight.flashLoan(address(loanToken), amount, address(this), data);

        assertEq(loanToken.balanceOf(address(this)), 0, "balanceOf");
        assertEq(loanToken.balanceOf(address(midnight)), amount, "balanceOf");
    }

    function testFlashLoanNotReimbursed(uint256 amount, bytes memory data) public {
        amount = bound(amount, 1, type(uint256).max);

        amountStored = amount;
        dataStored = data;
        discardToken = true;

        deal(address(loanToken), address(midnight), amount);
        vm.expectRevert(); // exact message depends on the token.
        midnight.flashLoan(address(loanToken), amount, address(this), data);
    }

    function onFlashLoan(address token, uint256 amount, bytes memory data) external {
        assertEq(token, address(loanToken), "wrong token");
        assertEq(amount, amountStored, "wrong amount");
        assertEq(data, dataStored, "wrong data");
        if (discardToken) SafeTransferLib.safeTransfer(token, address(0xdead), amount);
    }
}
