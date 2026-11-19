// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ISwapper} from "../../src/periphery/blue-swap-buy-callback/interfaces/ISwapper.sol";
import {IERC20Extended} from "../../src/periphery/blue-buy-callback/interfaces/IERC20Extended.sol";
import {ERC20Lib} from "../../src/periphery/libraries/ERC20Lib.sol";
import {SafeTransferLib} from "../../src/libraries/SafeTransferLib.sol";
import {CALLBACK_SUCCESS} from "../../src/libraries/ConstantsLib.sol";

/// @dev Test-only, permissionless route executor. Never leave funds here between calls.
contract GenericSwapper is ISwapper {
    error InsufficientOutput();

    /// @dev data = abi.encode(address target, bytes callData, address recipient). Input tokens must already be here.
    /// @dev Sends exactly minAmountOut to the caller, and excess output and unused input to recipient.
    function onSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes memory data)
        external
        returns (bytes32)
    {
        (address target, bytes memory callData, address recipient) = abi.decode(data, (address, bytes, address));
        ERC20Lib.safeApprove(tokenIn, target, amountIn);
        (bool success, bytes memory reason) = target.call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
        ERC20Lib.safeApprove(tokenIn, target, 0);
        uint256 output = IERC20Extended(tokenOut).balanceOf(address(this));
        require(output >= minAmountOut, InsufficientOutput());
        SafeTransferLib.safeTransfer(tokenOut, msg.sender, minAmountOut);
        if (output > minAmountOut) SafeTransferLib.safeTransfer(tokenOut, recipient, output - minAmountOut);
        if (tokenIn != tokenOut) {
            uint256 remainingInput = IERC20Extended(tokenIn).balanceOf(address(this));
            if (remainingInput > 0) SafeTransferLib.safeTransfer(tokenIn, recipient, remainingInput);
        }
        return CALLBACK_SUCCESS;
    }
}
