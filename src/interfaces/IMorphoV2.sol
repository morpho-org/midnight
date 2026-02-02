// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Obligation {
    address loanToken;
    // Must be sorted by address.
    Collateral[] collaterals;
    uint256 maturity;
    uint256 minCollateral; // quoted in loan token
}

struct Collateral {
    address token;
    uint256 lltv;
    address oracle;
}

struct Offer {
    Obligation obligation;
    bool buy;
    address maker;
    uint256 assets;
    uint256 obligationUnits;
    uint256 obligationShares;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @dev Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d TTM buckets.
/// @dev Fees are stored divided by FEE_STEP (1e12) to fit in 16 bits. Max fee is 1% (0.01e18).
struct ObligationState {
    uint128 totalUnits;
    uint128 totalShares;
    uint256 withdrawable;
    bool created;
    uint16[6] fees;
}

interface IMorphoV2 {}
