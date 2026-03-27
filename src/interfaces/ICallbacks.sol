// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Obligation} from "./IMidnight.sol";

interface ICallbacks {
    function onMidnightBuy(
        bytes32 obligationId,
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external;
    function onMidnightSell(
        bytes32 obligationId,
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external;
    function onMidnightLiquidate(
        bytes32 obligationId,
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external;
}

interface IFlashLoanCallback {
    function onMidnightFlashLoan(address token, uint256 amount, bytes memory data) external;
}
