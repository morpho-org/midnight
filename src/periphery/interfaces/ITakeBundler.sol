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

enum PermitKind {
    None,
    ERC2612,
    Permit2
}

struct TokenPermit {
    PermitKind kind;
    bytes data;
}

interface ITakeBundler {
    /// ERRORS ///
    error InconsistentObligation();
    error InconsistentSide();
    error InvalidPermitArrayLength();
    error OutOfOffers();
    error PctExceeded();
    error Unauthorized();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function buyUnitsTarget(address midnight, uint256 targetUnits, uint256 maxBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient, TokenPermit memory loanTokenPermit) external;
    function sellUnitsTarget(address midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient, TokenPermit[] memory collateralPermits) external;
    function buyBuyerAssetsTarget(address midnight, uint256 targetBuyerAssets, address taker, Take[] memory takes, CollateralTransfer[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient, TokenPermit memory loanTokenPermit) external;
    function sellSellerAssetsTarget(address midnight, uint256 targetSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] memory takes, CollateralTransfer[] memory collateralSupplies, uint256 referralFeePct, address referralFeeRecipient, TokenPermit[] memory collateralPermits) external;
    // forgefmt: disable-end
}
