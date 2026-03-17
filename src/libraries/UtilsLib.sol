// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library UtilsLib {
    /// @dev Returns true if at most one of `x` and `y` is nonzero.
    function atMostOneNonZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := gt(add(iszero(x), iszero(y)), 0)
        }
    }

    /// @dev Returns min(a, b).
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns hash(... hash(leafHash, proof[0]), ..., proof[n]) == root.
    /// @dev Hash sorts the inputs lexicographically.
    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] memory proof) internal pure returns (bool) {
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = commutativeHash(currentHash, proof[i]);
        }
        return currentHash == root;
    }

    /// @dev Returns the keccak256 hash of the sorted concatenation of `a` and `b`.
    function commutativeHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        if (a > b) (a, b) = (b, a);
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "uint256 overflows uint128");
        // forge-lint: disable-next-item(unsafe-typecast) as x is less than type(uint128).max
        return uint128(x);
    }

    function toUint120(uint256 x) internal pure returns (uint120) {
        require(x <= type(uint120).max, "uint256 overflows uint120");
        // forge-lint: disable-next-item(unsafe-typecast) as x is less than type(uint120).max
        return uint120(x);
    }

    function toInt136(int256 x) internal pure returns (int136) {
        require(x >= type(int136).min && x <= type(int136).max, "int256 overflows int136");
        // forge-lint: disable-next-item(unsafe-typecast) as x is within int136 range
        return int136(x);
    }

    function toInt136(uint256 x) internal pure returns (int136) {
        require(x <= uint136(type(int136).max), "uint256 overflows int136");
        // forge-lint: disable-next-item(unsafe-typecast) as x is within int136 range
        return int136(uint136(x));
    }

    function toInt256(uint256 x) internal pure returns (int256) {
        require(x <= uint256(type(int256).max), "uint256 overflows int256");
        // forge-lint: disable-next-item(unsafe-typecast) as x is less than type(int256).max
        return int256(x);
    }

    function countBits(uint128 x) internal pure returns (uint256) {
        unchecked {
            x = x - ((x >> 1) & 0x55555555555555555555555555555555);
            x = (x & 0x33333333333333333333333333333333) + ((x >> 2) & 0x33333333333333333333333333333333);
            x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
            return (x * 0x01010101010101010101010101010101) >> 120;
        }
    }

    function msb(uint256 bitmap) internal pure returns (uint256 res) {
        assembly {
            res := sub(255, clz(bitmap))
        }
    }

    function negativePart(int256 x) internal pure returns (uint256 res) {
        assembly {
            res := mul(shr(255, x), sub(0, x))
        }
    }
}
