// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.4;

library ErrorsLib {
    error AlreadyConsumed();
    error BuyerGatedFromIncreasingCredit();
    error BuyerPendingFeeExceedsCredit();
    error CollateralParamsNotSorted();
    error ConsumedBuyerAssets();
    error ConsumedSellerAssets();
    error ConsumedUnits();
    error ContinuousFeeTooHigh();
    error Expired();
    error FeeNotMultipleOfFeeStep();
    error InconsistentInput();
    error InvalidCallback();
    error InvalidFeeIndex();
    error InvalidMaxLif();
    error InvalidNonce();
    error InvalidProof();
    error InvalidSession();
    error InvalidSignature();
    error LiquidatorGatedFromLiquidating();
    error LltvNotAllowed();
    error MakerCreditOrDebtIncreased();
    error MultipleNonZeroMax();
    error NoCollateralParams();
    error NotApproved();
    error NotLiquidatable();
    error NotRatified();
    error ObligationNotCreated();
    error OfferExpired();
    error OfferNotStarted();
    error OnlyFeeClaimer();
    error OnlyFeeSetter();
    error OnlyRoleSetter();
    error RatifierUnauthorized();
    error RecoveryCloseFactorConditionsViolated();
    error SelfTake();
    error SellerGatedFromIncreasingDebt();
    error SellerIsLiquidatable();
    error TakerUnauthorized();
    error TooManyActivatedCollaterals();
    error TooManyCollateralParams();
    error TradingFeeTooHigh();
    error Unauthorized();
    error UnhealthyBorrower();
}
