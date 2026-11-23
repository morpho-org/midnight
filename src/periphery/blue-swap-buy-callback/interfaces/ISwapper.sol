// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface ISwapper {
    /// @dev The caller has sent amountIn tokenIn to this contract. Transfer at least minAmountOut tokenOut to msg.sender and return Midnight's CALLBACK_SUCCESS. Implementations must validate callers if they expose any privileged funds.
    function onSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes memory data)
        external
        returns (bytes32);
}
