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

/// @dev Identifies how a token is permitted (and pulled) by the bundler. The signed value (ERC2612)
/// or `permitted.amount` (Permit2) must be at least the amount the bundler is about to pull, which
/// is fixed by the surrounding call (`maxBuyerAssets` / `targetBuyerAssets` / `collateralSupplies[i]`).
/// - None: no permit is run; the bundler pulls via a standard ERC20 `transferFrom`. `data` is ignored.
/// - ERC2612: `data = abi.encode(uint256 deadline, uint8 v, bytes32 r, bytes32 s)`. Bundler calls
///   `token.permit(owner=msg.sender, spender=this, value=<pull amount>, deadline, v, r, s)`, then
///   performs a standard ERC20 pull. Permit reverts are tolerated to handle a third party having
///   already consumed the permit.
/// - Permit2: `data = abi.encode(uint256 nonce, uint256 deadline, bytes signature)`. Bundler calls
///   `Permit2.permitTransferFrom(permit{token, amount=<pull amount>, nonce, deadline},
///   transferDetails{to=this, requestedAmount=<pull amount>}, owner=msg.sender, signature)`. The
///   call IS the pull, so no separate transfer step is performed. Reverts propagate.
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
