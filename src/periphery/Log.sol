// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

uint256 constant MAX_DATA_LENGTH = 1_000_000;

contract Log {
    event Data(bytes data);

    error DataTooLong();

    /// @notice Logs the calldata.
    /// @dev Payable to reduce gas cost.
    fallback() external payable {
        require(msg.data.length <= MAX_DATA_LENGTH, DataTooLong());
        emit Data(msg.data);
    }
}
