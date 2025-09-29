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
        uint256 N_ROUNDS = 10;
        assembly {
            let acc := x

            for { let i := 0 } lt(i, N_ROUNDS) { i := add(i, 1) } {
                switch mod(i, 2)
                case 0 { y := add(y, div(acc, add(i, 1))) }
                default { y := sub(y, div(acc, add(i, 1))) }
                acc := div(mul(x, acc), WAD_INT)
            }
        }
    }
}
