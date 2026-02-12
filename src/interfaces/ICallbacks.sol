// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Obligation} from "./IMorphoV2.sol";

interface ICallbacks {
    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external;
    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external;
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
