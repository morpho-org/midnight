// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {Obligation} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract Utils {
    function hashObligation(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function getBit(uint128 bitmap, uint256 bit) external pure returns (bool) {
        return bitmap & (1 << bit) != 0;
    }

    function setBit(uint128 bitmap, uint256 bit) external pure returns (uint128) {
        return UtilsLib.setBit(bitmap, bit);
    }

    function clearBit(uint128 bitmap, uint256 bit) external pure returns (uint128) {
        return UtilsLib.clearBit(bitmap, bit);
    }

    function msb(uint128 bitmap) external pure returns (uint256) {
        return UtilsLib.msb(bitmap);
    }

    function emptyOffer() external pure returns (Offer memory) {
        Offer memory offer;
        return offer;
    }
}
