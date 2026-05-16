// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer, Market} from "../../interfaces/IMidnight.sol";

struct Take {
    uint256 units;
    Offer offer;
    bytes ratifierData;
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

struct CollateralWithdrawal {
    uint256 collateralIndex;
    uint256 assets;
}

struct CollateralSupply {
    uint256 collateralIndex;
    uint256 assets;
    TokenPermit permit;
}

interface IMidnightBundles {
    /// ERRORS ///
    error InconsistentMarket();
    error InconsistentSide();
    error OutOfOffers();
    error PctExceeded();
    error SellerAssetsTooLow();
    error Unauthorized();
    error UnitsTooHigh();
    error UnitsTooLow();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function buyWithUnitsTargetAndWithdrawCollateral(address midnight, uint256 targetUnits, uint256 maxBuyerAssets, address taker, TokenPermit memory loanTokenPermit, Take[] memory takes, CollateralWithdrawal[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function supplyCollateralAndSellWithUnitsTarget(address midnight, uint256 targetUnits, uint256 minSellerAssets, address taker, address receiverIfTakerIsSeller, CollateralSupply[] memory collateralSupplies, Take[] memory takes, uint256 referralFeePct, address referralFeeRecipient) external;
    function buyWithAssetsTargetAndWithdrawCollateral(address midnight, uint256 targetBuyerAssets, uint256 minUnits, address taker, TokenPermit memory loanTokenPermit, Take[] memory takes, CollateralWithdrawal[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    function supplyCollateralAndSellWithAssetsTarget(address midnight, uint256 targetSellerAssets, uint256 maxUnits, address taker, address receiverIfTakerIsSeller, CollateralSupply[] memory collateralSupplies, Take[] memory takes, uint256 referralFeePct, address referralFeeRecipient) external;
    function repayAndWithdrawCollateral(address midnight, Market memory market, uint256 assets, address onBehalf, TokenPermit memory loanTokenPermit, CollateralWithdrawal[] memory collateralWithdrawals, address collateralReceiver, uint256 referralFeePct, address referralFeeRecipient) external;
    // forgefmt: disable-end
}
