// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

interface IERC20Approve {
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

library SafeApproveLib {
    error ApproveReturnedFalse();

    /// @dev Skips the approval when the current allowance is already at least 2^95 - 1.
    /// @dev Resets to 0 before re-approving to support USDT-like tokens.
    function forceApproveMax(address token, address spender) internal {
        if (IERC20Approve(token).allowance(address(this), spender) >= type(uint96).max / 2) return;
        safeApprove(token, spender, 0);
        safeApprove(token, spender, type(uint256).max);
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20Approve.approve, (spender, value)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ApproveReturnedFalse());
    }
}
