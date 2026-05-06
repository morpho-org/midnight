// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Obligation} from "./IMidnight.sol";

// forgefmt: disable-start
interface IBuyCallback {
    function onBuy(bytes32 id, Obligation memory obligation, address buyer, uint256 buyerAssets, uint256 units, bytes memory data) external returns (bytes32);
}

interface ISellCallback {
    function onSell(bytes32 id, Obligation memory obligation, address seller, uint256 sellerAssets, uint256 units, bytes memory data) external returns (bytes32);
}

interface ILiquidateCallback {
    function onLiquidate(bytes32 id, Obligation memory obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes memory data) external returns (bytes32);
}

interface IRepayCallback {
    function onRepay(bytes32 id, Obligation memory obligation, uint256 units, address onBehalf, bytes memory data) external returns (bytes32);
}

interface IFlashLoanCallback {
    function onFlashLoan(address[] memory tokens, uint256[] memory assets, bytes memory data) external returns (bytes32);
}
// forgefmt: disable-end
