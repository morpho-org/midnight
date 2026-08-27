// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";

contract FlashLoanTest is BaseTest, IFlashLoanCallback {
    address[] internal recordedTokens;
    uint256[] internal recordedAmounts;
    address internal recordedCaller;
    bytes internal recordedData;
    bool internal discardToken = false;

    function testFlashLoan(uint256 amount0, uint256 amount1, uint256 amount2, bytes memory data, address caller)
        public
    {
        amount0 = bound(amount0, 1, type(uint256).max);
        amount1 = bound(amount1, 1, type(uint256).max);
        amount2 = bound(amount2, 1, type(uint256).max);

        address[] memory tokens = new address[](3);
        tokens[0] = address(loanToken);
        tokens[1] = address(collateralToken1);
        tokens[2] = address(collateralToken2);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount0;
        amounts[1] = amount1;
        amounts[2] = amount2;

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(midnight), amounts[i]);
        }

        vm.expectEmit();
        emit EventsLib.FlashLoan(caller, tokens, amounts, address(this));

        vm.prank(caller);
        midnight.flashLoan(tokens, amounts, address(this), data);

        assertEq(recordedTokens.length, tokens.length, "recorded tokens length");
        assertEq(recordedAmounts.length, amounts.length, "recorded amounts length");
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(recordedTokens[i], tokens[i], "recorded token");
            assertEq(recordedAmounts[i], amounts[i], "recorded amount");
            assertEq(ERC20(tokens[i]).balanceOf(address(this)), 0, "balanceOf(this)");
            assertEq(ERC20(tokens[i]).balanceOf(address(midnight)), amounts[i], "balanceOf(midnight)");
        }
        assertEq(recordedCaller, caller, "recorded caller");
        assertEq(recordedData, data, "recorded data");
    }

    function testFlashLoanNotReimbursed(uint256 amount0, uint256 amount1, uint256 amount2, bytes memory data) public {
        amount0 = bound(amount0, 1, type(uint256).max);
        amount1 = bound(amount1, 1, type(uint256).max);
        amount2 = bound(amount2, 1, type(uint256).max);

        address[] memory tokens = new address[](3);
        tokens[0] = address(loanToken);
        tokens[1] = address(collateralToken1);
        tokens[2] = address(collateralToken2);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount0;
        amounts[1] = amount1;
        amounts[2] = amount2;

        discardToken = true;

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(midnight), amounts[i]);
        }

        vm.expectRevert(); // exact message depends on the token.
        midnight.flashLoan(tokens, amounts, address(this), data);
    }

    function testFlashLoanInconsistentInput(uint256 amount0, uint256 amount1, bytes memory data) public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(loanToken);
        tokens[1] = address(collateralToken1);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount0;
        amounts[1] = amount1;

        vm.expectRevert(IMidnight.InconsistentInput.selector);
        midnight.flashLoan(tokens, amounts, address(this), data);

        // Also revert the other way around: more tokens than amounts.
        address[] memory tokens2 = new address[](3);
        tokens2[0] = address(loanToken);
        tokens2[1] = address(collateralToken1);
        tokens2[2] = address(collateralToken2);
        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = amount0;
        amounts2[1] = amount1;

        vm.expectRevert(IMidnight.InconsistentInput.selector);
        midnight.flashLoan(tokens2, amounts2, address(this), data);
    }

    function testFlashLoanWrongCallbackReturnValue(uint256 amount0, uint256 amount1, bytes memory data) public {
        amount0 = bound(amount0, 1, type(uint256).max);
        amount1 = bound(amount1, 1, type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(loanToken);
        tokens[1] = address(collateralToken1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(midnight), amounts[i]);
        }

        address callback = address(new InvalidFlashLoanCallback());

        vm.expectRevert(IMidnight.WrongFlashLoanCallbackReturnValue.selector);
        midnight.flashLoan(tokens, amounts, callback, data);
    }

    function onFlashLoan(address caller, address[] memory tokens, uint256[] memory amounts, bytes memory data)
        external
        returns (bytes32)
    {
        recordedTokens = tokens;
        recordedAmounts = amounts;
        recordedCaller = caller;
        recordedData = data;
        if (discardToken) {
            for (uint256 i = 0; i < tokens.length; i++) {
                SafeTransferLib.safeTransfer(tokens[i], address(0xdead), amounts[i]);
            }
        }
        return CALLBACK_SUCCESS;
    }
}

contract InvalidFlashLoanCallback is IFlashLoanCallback {
    function onFlashLoan(address, address[] memory, uint256[] memory, bytes memory) external pure returns (bytes32) {
        return bytes32(0);
    }
}
