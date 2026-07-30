// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IERC20Extended} from "./interfaces/IERC20Extended.sol";

library ApproveLib {
    error ApproveReturnedFalse();

    /// @dev Not checking the code size because Midnight's transfers do it already.
    function safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20Extended.approve, (spender, value)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ApproveReturnedFalse());
    }
}
