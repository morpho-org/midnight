// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library MathLib {
    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns max(0, x - y).
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns hash(... hash(leafHash, proof[0]), ..., proof[n]) == root.
    /// @dev Hash sorts the inputs lexicographically.
    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] memory proof) internal pure returns (bool) {
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = keccak256(sort(currentHash, proof[i]));
        }
        return currentHash == root;
    }

    function messageSigner(bytes32 data, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", data));
        address tentativeSigner = ecrecover(messageHash, v, r, s);
        require(tentativeSigner != address(0), "invalid signature");
        return tentativeSigner;
    }

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }
}
