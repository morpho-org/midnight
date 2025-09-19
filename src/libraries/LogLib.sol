// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title LogLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to approximate the log function.
library LogLib {
    int256 internal constant WAD_INT = 1e18;

    /// @dev Returns an approximation of ln.
    function wLn(int256 x) internal pure returns (int256 y) {
        unchecked {
            y = x - x * x / (2*WAD_INT) + x * x / WAD_INT * x / (3*WAD_INT);
        }
    }
}
