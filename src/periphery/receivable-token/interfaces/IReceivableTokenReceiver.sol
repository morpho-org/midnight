// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

/// @dev Implemented by non-whitelisted accounts that receive receivable tokens.
interface IReceivableTokenReceiver {
    /// @dev Called by the token after `amount` tokens have been transferred from `from` to the receiver. The receiver
    /// must redeem them or transfer them to a whitelisted account before returning, otherwise the transfer reverts.
    function onReceivableTokenReceived(address from, uint256 amount) external;
}
