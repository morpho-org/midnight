// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Obligation, Offer} from "./IMidnight.sol";

interface ICallbacks {
    /// @dev The signer is address(1) if the offer is already validate or the callback is for the taker.
    /// @dev Otherwise, the callback must validate the offer.
    function onBuy(
        Offer memory offer,
        address signer,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external returns (bytes32);

    /// @dev The signer is address(1) if the offer is already validate or the callback is for the taker.
    /// @dev Otherwise, the callback must validate the offer.
    function onSell(
        Offer memory offer,
        address signer,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external returns (bytes32);
    function onLiquidate(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external;
}

interface IFlashLoanCallback {
    function onFlashLoan(address token, uint256 amount, bytes memory data) external;
}
