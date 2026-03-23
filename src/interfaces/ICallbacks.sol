// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Obligation, Offer} from "./IMidnight.sol";

interface ICallbacks {
    function onBuy(
        Offer memory offer,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external returns (bytes32);

    function onSell(
        Offer memory offer,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
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
