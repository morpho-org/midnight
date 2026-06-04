// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Market} from "./IMidnight.sol";

// forgefmt: disable-start
interface IBuyCallback {
    function onBuy(bytes32 id, Market memory market, uint256 buyerAssets, uint256 units, uint256 pendingFeeIncrease, address buyer, bytes memory data) external returns (bytes32);
}

interface ISellCallback {
    function onSell(bytes32 id, Market memory market, uint256 sellerAssets, uint256 units, uint256 pendingFeeDecrease, address seller, address receiver, bytes memory data) external returns (bytes32);
}

interface ILiquidateCallback {
    function onLiquidate(address caller, bytes32 id, Market memory market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, bytes memory data, uint256 badDebt) external returns (bytes32);
}

interface IRepayCallback {
    function onRepay(bytes32 id, Market memory market, uint256 units, address onBehalf, bytes memory data) external returns (bytes32);
}

interface IFlashLoanCallback {
    function onFlashLoan(address caller, address[] memory tokens, uint256[] memory assets, bytes memory data) external returns (bytes32);
}
// forgefmt: disable-end
