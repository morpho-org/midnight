// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer, Obligation} from "../../interfaces/IMidnight.sol";

struct Take {
    uint256 units;
    Offer offer;
    bytes ratifierData;
}

struct CollateralTransfer {
    uint256 collateralIndex;
    uint256 assets;
}

enum PermitKind {
    None,
    ERC2612,
    Permit2
}

struct TokenPermit {
    PermitKind kind;
    bytes data;
}

interface IMidnightBundles {
    /// ERRORS ///
    error InconsistentObligation();
    error InconsistentSide();
    error InvalidPermitArrayLength();
    error OutOfOffers();
    error PctExceeded();
    error SellerAssetsTooLow();
    error Unauthorized();
    error UnitsTooHigh();
    error UnitsTooLow();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function unitsTargetBuyAndWithdrawCollateral(address midnight, uint256 targetUnits, uint256 maxBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient, TokenPermit memory loanTokenPermit) external;
    function supplyCollateralAndUnitsTargetSell(address midnight, uint256 targetUnits, uint256 minSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient, TokenPermit[] memory collateralPermits) external;
    function assetsTargetBuyAndWithdrawCollateral(address midnight, uint256 targetBuyerAssets, uint256 minUnits, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient, TokenPermit memory loanTokenPermit) external;
    function supplyCollateralAndAssetsTargetSell(address midnight, uint256 targetSellerAssets, uint256 maxUnits, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient, TokenPermit[] memory collateralPermits) external;
    function repayAndWithdrawCollateral(address midnight, Obligation memory obligation, uint256 units, address onBehalf, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, TokenPermit memory loanTokenPermit) external;
    // forgefmt: disable-end
}
