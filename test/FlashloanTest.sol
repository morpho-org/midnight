// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {IFlashLoanCallback} from "../src/interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";

contract FlashLoanTest is BaseTest, IFlashLoanCallback {
    address[] internal tokensStored;
    uint256[] internal amountsStored;
    bytes internal dataStored;
    bool internal discardToken = false;

    function testFlashLoan(uint256 amount0, uint256 amount1, uint256 amount2, bytes memory data) public {
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

        tokensStored = tokens;
        amountsStored = amounts;
        dataStored = data;

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(midnight), amounts[i]);
        }

        midnight.flashLoan(tokens, amounts, address(this), data);

        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(ERC20(tokens[i]).balanceOf(address(this)), 0, "balanceOf(this)");
            assertEq(ERC20(tokens[i]).balanceOf(address(midnight)), amounts[i], "balanceOf(midnight)");
        }
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

        tokensStored = tokens;
        amountsStored = amounts;
        dataStored = data;
        discardToken = true;

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(midnight), amounts[i]);
        }

        vm.expectRevert(); // exact message depends on the token.
        midnight.flashLoan(tokens, amounts, address(this), data);
    }

    function onFlashLoan(address[] memory tokens, uint256[] memory amounts, bytes memory data)
        external
        returns (bytes32)
    {
        assertEq(tokens.length, tokensStored.length, "wrong tokens length");
        assertEq(amounts.length, amountsStored.length, "wrong amounts length");
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i], tokensStored[i], "wrong token");
            assertEq(amounts[i], amountsStored[i], "wrong amount");
        }
        assertEq(data, dataStored, "wrong data");
        if (discardToken) {
            for (uint256 i = 0; i < tokens.length; i++) {
                SafeTransferLib.safeTransfer(tokens[i], address(0xdead), amounts[i]);
            }
        }
        return CALLBACK_SUCCESS;
    }
}
