// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer, Obligation} from "../../interfaces/IMidnight.sol";

struct Take {
    uint256 units;
    Offer offer;
    bytes ratifierData;
    bytes32 root;
    bytes32[] proof;
}

struct CollateralTransfer {
    uint256 collateralIndex;
    uint256 assets;
}

interface IMidnightBundles {
    /// ERRORS ///
    error InconsistentObligation();
    error InconsistentSide();
    error OutOfOffers();
    error PctExceeded();
    error Unauthorized();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function unitsTargetBuyAndWithdrawCollateral(address midnight, uint256 targetUnits, uint256 maxBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function supplyCollateralAndUnitsTargetSell(address midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient) external;
    function assetsTargetBuyAndWithdrawCollateral(address midnight, uint256 targetBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function supplyCollateralAndAssetsTargetSell(address midnight, uint256 targetSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient) external;
    function repayAndWithdrawCollateral(address midnight, Obligation memory obligation, uint256 units, address onBehalf, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver) external;
    // forgefmt: disable-end
}
