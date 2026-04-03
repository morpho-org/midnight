// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library ErrorsLib {
    error BuyerAssetsAboveMax();
    error BuyerAssetsBelowMin();
    error BuyerGatedFromCredit();
    error BuyerPriceTooHigh();
    error CollateralsNotSorted();
    error ConsumedTooLow();
    error ContinuousFeeTooHigh();
    error Crossed();
    error FeeNotMultipleOfStep();
    error InconsistentInput();
    error InsufficientLiquidity();
    error InvalidMaxLif();
    error InvalidProof();
    error InvalidSession();
    error InvalidSignature();
    error InvalidTradingFeeIndex();
    error LiquidatorGated();
    error LltvNotAllowed();
    error MaxBuyerAssetsExceeded();
    error MaxSellerAssetsExceeded();
    error MaxUnitsExceeded();
    error NoCollaterals();
    error NotLiquidatable();
    error ObligationNotCreated();
    error OfferExpired();
    error OfferNotStarted();
    error OnlyFeeSetter();
    error OnlyOwner();
    error OverflowUint128();
    error PendingFeeExceedsCredit();
    error PriceGreaterThanOne();
    error RecoveryCloseFactorViolated();
    error SameBuyerAndSeller();
    error SellerAssetsAboveMax();
    error SellerAssetsBelowMin();
    error SellerGatedFromDebt();
    error SellerUnhealthy();
    error Sstore2Failed();
    error TickOutOfRange();
    error TokenHasNoCode();
    error TooManyCollaterals();
    error TooManyCollateralsPerBorrower();
    error TransferFailed();
    error TransferFromFailed();
    error Unauthorized();
    error UnhealthyBorrower();
    error TradingFeeTooHigh();
    error UnitsAboveMax();
    error UnitsBelowMin();
}
