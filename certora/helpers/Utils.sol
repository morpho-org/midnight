// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";
import {
    CALLBACK_SUCCESS,
    LIQUIDATION_CURSOR_LOW,
    LIQUIDATION_CURSOR_HIGH,
    maxTradingFee as _maxTradingFee,
    maxLif as _maxLif
} from "../../src/libraries/ConstantsLib.sol";

contract Utils {
    function hashMarket(Market memory market) external pure returns (bytes32) {
        return HashLib.hashMarket(market);
    }

    // Wraps `HashLib.hashOffer` directly so CVL specs can expose the real EIP-712 offer hash
    // envfree. Used by OfferTreeMembership.spec as the leaf id. A `keccak256(abi.encode(offer))`
    // reimplementation would be a *different* hash (no typehash prefix, no inner hashing of
    // market/callbackData), so we forward to the real library function.
    function hashOffer(Offer memory offer) external pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof)
        external
        pure
        returns (bool)
    {
        return HashLib.isLeaf(root, leafHash, leafIndex, proof);
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

    function countBits(uint128 bitmap) external pure returns (uint256) {
        return UtilsLib.countBits(bitmap);
    }

    function emptyOffer() external pure returns (Offer memory) {
        Offer memory offer;
        return offer;
    }

    function callbackSuccess() external pure returns (bytes32) {
        return CALLBACK_SUCCESS;
    }

    function maxTradingFee(uint256 index) external pure returns (uint256) {
        return _maxTradingFee(index);
    }

    function maxLif(uint256 lltv, uint256 cursor) external pure returns (uint256) {
        return _maxLif(lltv, cursor);
    }

    function liquidationCursorLow() external pure returns (uint256) {
        return LIQUIDATION_CURSOR_LOW;
    }

    function liquidationCursorHigh() external pure returns (uint256) {
        return LIQUIDATION_CURSOR_HIGH;
    }
}
