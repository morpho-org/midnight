// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer} from "../../interfaces/IMidnight.sol";

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

interface ITakeBundler {
    /// ERRORS ///
    error InconsistentObligation();
    error InconsistentSide();
    error OutOfOffers();
    error PctExceeded();
    error SellerAssetsTooLow();
    error Unauthorized();
    error UnitsTooHigh();
    error UnitsTooLow();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function buyUnitsTarget(address midnight, uint256 targetUnits, uint256 maxBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function sellUnitsTarget(address midnight, uint256 targetUnits, uint256 minSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient) external;
    function buyBuyerAssetsTarget(address midnight, uint256 targetBuyerAssets, uint256 minUnits, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function sellSellerAssetsTarget(address midnight, uint256 targetSellerAssets, uint256 maxUnits, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient) external;
    // forgefmt: disable-end
}
