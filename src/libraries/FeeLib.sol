// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

/// @title FeeLib
/// @notice Library for packing/unpacking fees in a single word.
/// @dev Layout:
///   - Bits 0-119: 6 trading fees packed (20 bits each) (Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d)
///   - Bits 120-184: interest fees (64 bits).
/// @dev Trading fees are stored divided by 1e12 to fit in 20 bits.
/// @dev Trading fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d.
library FeeLib {
    uint256 internal constant TRADING_FEE_STEP = 1e12;
    uint256 internal constant TRADING_FEE_BITS = 20;
    uint256 internal constant TRADING_FEE_MASK = 0xFFFFF;
    uint256 internal constant INTEREST_FEE_BITS = 64;
    uint256 internal constant INTEREST_FEE_MASK = 0xFFFFFFFFFFFFFFFF;

    /// @dev Returns the fee at the given index, scaled back to WAD precision.
    function getTradingFee(uint256 feeStorage, uint256 index) internal pure returns (uint256) {
        return ((feeStorage >> (index * TRADING_FEE_BITS)) & TRADING_FEE_MASK) * TRADING_FEE_STEP;
    }

    /// @dev Returns the interest fee.
    function getInterestFee(uint256 feeStorage) internal pure returns (uint256) {
        return (feeStorage >> 120) & INTEREST_FEE_MASK;
    }

    /// @dev Returns the updated packed fee storage value.
    function setTradingFee(uint256 feeStorage, uint256 index, uint256 fee) internal pure returns (uint256) {
        require(fee % TRADING_FEE_STEP == 0, "fee should be a multiple of 1e12");
        uint256 shift = index * TRADING_FEE_BITS;
        uint256 cleared = feeStorage & ~(TRADING_FEE_MASK << shift);
        uint256 packedFee = (fee / TRADING_FEE_STEP) << shift;
        return cleared | packedFee;
    }

    /// @dev Returns the updated packed fee storage value.
    function setInterestFee(uint256 feeStorage, uint256 interestFee) internal pure returns (uint256) {
        return (feeStorage & ~(INTEREST_FEE_MASK << 120)) | (interestFee << 120);
    }
}
