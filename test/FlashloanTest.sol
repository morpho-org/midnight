// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";

contract FlashLoanTest is BaseTest, IFlashLoanCallback {
    uint256 internal amountStored;
    bytes internal dataStored;
    bool internal discardToken = false;

    function testFlashLoan(uint256 amount, bytes memory data) public {
        amount = bound(amount, 1, type(uint256).max);
        amountStored = amount;
        dataStored = data;

        deal(address(loanToken), address(midnight), amount);
        address[] memory tokens = new address[](1);
        tokens[0] = address(loanToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        midnight.flashLoan(tokens, amounts, address(this), data);

        assertEq(loanToken.balanceOf(address(this)), 0, "balanceOf");
        assertEq(loanToken.balanceOf(address(midnight)), amount, "balanceOf");
    }

    function testFlashLoanNotReimbursed(uint256 amount, bytes memory data) public {
        amount = bound(amount, 1, type(uint256).max);

        amountStored = amount;
        dataStored = data;
        discardToken = true;

        deal(address(loanToken), address(midnight), amount);
        address[] memory tokens = new address[](1);
        tokens[0] = address(loanToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.expectRevert(); // exact message depends on the token.
        midnight.flashLoan(tokens, amounts, address(this), data);
    }

    function onFlashLoan(address[] memory tokens, uint256[] memory amounts, bytes memory data)
        external
        returns (bytes32)
    {
        assertEq(tokens.length, 1, "wrong tokens length");
        assertEq(amounts.length, 1, "wrong amounts length");
        assertEq(tokens[0], address(loanToken), "wrong token");
        assertEq(amounts[0], amountStored, "wrong amount");
        assertEq(data, dataStored, "wrong data");
        if (discardToken) SafeTransferLib.safeTransfer(tokens[0], address(0xdead), amounts[0]);
        return CALLBACK_SUCCESS;
    }
}
