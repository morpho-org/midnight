// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

/// @title FeeLib
/// @notice Library for packing/unpacking trading fees in a single uint256.
/// @dev Storage layout:
///   - Bit 255: activated flag
///   - Bits 0-119: 6 trading fees packed (20 bits each)
///   - Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d
/// @dev Fees are stored divided by 1e12 to fit in 20 bits.
library FeeLib {
    uint256 internal constant FEE_STEP = 1e12;
    uint256 internal constant FEE_BITS = 20;
    uint256 internal constant FEE_MASK = 0xFFFFF;
    uint256 internal constant ACTIVATED_MASK = 1 << 255;

    /// @dev Returns whether the fee storage is activated.
    function getActivated(uint256 feeStorage) internal pure returns (bool) {
        return feeStorage & ACTIVATED_MASK != 0;
    }

    /// @dev Returns the fee at the given index, scaled back to WAD precision.
    function getFee(uint256 feeStorage, uint256 index) internal pure returns (uint256) {
        return ((feeStorage >> (index * FEE_BITS)) & FEE_MASK) * FEE_STEP;
    }

    /// @dev Returns the updated packed fee storage value.
    function setFee(uint256 feeStorage, uint256 index, uint256 fee) internal pure returns (uint256) {
        require(fee % FEE_STEP == 0, "fee should be a multiple of 1e12");
        uint256 shift = index * FEE_BITS;
        uint256 cleared = feeStorage & ~(FEE_MASK << shift);
        uint256 packedFee = (fee / FEE_STEP) << shift;
        return cleared | packedFee;
    }

    /// @dev Returns the updated packed fee storage value.
    function setActivated(uint256 feeStorage, bool activated) internal pure returns (uint256) {
        return (feeStorage & ~ACTIVATED_MASK) | boolToUint256(activated) << 255;
    }

    function boolToUint256(bool b) internal pure returns (uint256 res) {
        assembly {
            res := b
        }
    }
}
