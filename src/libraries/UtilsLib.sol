// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library UtilsLib {
    /// @dev Returns true if at most one of `x` and `y` is nonzero.
    function atMostOneNonZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := gt(add(iszero(x), iszero(y)), 0)
        }
    }

    /// @dev Returns true if at most one of `x`, `y`, `z` is nonzero.
    function atMostOneNonZero(uint256 a, uint256 b, uint256 c) internal pure returns (bool z) {
        assembly {
            z := gt(add(add(iszero(a), iszero(b)), iszero(c)), 1)
        }
    }

    /// @dev Returns true if at most one of `a`, `b`, `c`, `d` is nonzero.
    function atMostOneNonZero(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (bool z) {
        assembly {
            z := gt(add(add(add(iszero(a), iszero(b)), iszero(c)), iszero(d)), 2)
        }
    }

    /// @dev Returns min(a, b).
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), gt(y, x)))
        }
    }

    function hashMessage(bytes32 root) internal pure returns (bytes32 hash) {
        assembly {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, root)
            hash := keccak256(0x00, 0x3c)
        }
    }

    function hashObligation(Obligation memory obligation) internal pure returns (bytes32 hash) {
        uint256 length = 32 * 6 + 3 * 32 * obligation.collaterals.length;
        uint256 ptr;
        uint256 initPtr;
        uint256 chainId = obligation.chainId;
        address loanToken = obligation.loanToken;
        uint256 maturity = obligation.maturity;
        uint256 collateralLength = obligation.collaterals.length;
        assembly {
            ptr := mload(0x40)
            mstore(0x40, add(ptr, length))
            initPtr := ptr

            mstore(ptr, 0x20)
            ptr := add(ptr, 0x20)
            mstore(ptr, chainId)
            ptr := add(ptr, 0x20)
            mstore(ptr, loanToken)
            ptr := add(ptr, 0x20)
            mstore(ptr, 0x80)
            ptr := add(ptr, 0x20)
            mstore(ptr, maturity)
            ptr := add(ptr, 0x20)
            mstore(ptr, collateralLength)
            ptr := add(ptr, 0x20)
        }
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            address token = obligation.collaterals[i].token;
            uint256 lltv = obligation.collaterals[i].lltv;
            address oracle = obligation.collaterals[i].oracle;
            assembly {
                mstore(ptr, token)
                ptr := add(ptr, 0x20)
                mstore(ptr, lltv)
                ptr := add(ptr, 0x20)
                mstore(ptr, oracle)
                ptr := add(ptr, 0x20)
            }
        }
        assembly {
            hash := keccak256(initPtr, length)
        }
    }
}
