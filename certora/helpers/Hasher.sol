// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

// Comparing the used implementation with the reference implementation found at
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/765b288a6a273f8c267adcd409094212dbd5e3cb/contracts/utils/cryptography/MerkleProof.sol#L57-L63
contract Hasher {
    function usedKeccak256(bytes32 x, bytes32 y) external pure returns (bytes32) {
        return keccak256(UtilsLib.sort(x, y));
    }

    function commutativeKeccak256(bytes32 a, bytes32 b) public pure returns (bytes32) {
        return a < b ? efficientKeccak256(a, b) : efficientKeccak256(b, a);
    }

    function efficientKeccak256(bytes32 a, bytes32 b) public pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
