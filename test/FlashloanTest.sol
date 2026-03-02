// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";

contract FlashLoanTest is BaseTest, IFlashLoanCallback {
    uint256 internal amountStored;
    bytes internal dataStored;

    function testFlashLoan(uint256 amount, bytes memory data) public {
        amountStored = amount;
        dataStored = data;

        deal(address(loanToken), address(midnight), amount);
        midnight.flashLoan(address(loanToken), amount, address(this), data);

        assertEq(loanToken.balanceOf(address(this)), 0, "balanceOf");
        assertEq(loanToken.balanceOf(address(midnight)), amount, "balanceOf");
    }

    function onFlashLoan(address token, uint256 amount, bytes memory data) external {
        assertEq(token, address(loanToken), "wrong token");
        assertEq(amount, amountStored, "wrong amount");
        assertEq(data, dataStored, "wrong data");
        ERC20(token).approve(address(midnight), amount);
    }
}
