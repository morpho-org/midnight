// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

uint256 constant MAX_DATA_LENGTH = 1_000_000;

// forge-lint: disable-next-item(locked-ether) as Log is a calldata sink that is never meant to receive value: the
// fallback is payable purely to skip the callvalue check, and the contract tracks no balance to withdraw.
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
