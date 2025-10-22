// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {Seizure, Obligation} from "./IMorphoV2.sol";

interface ICallbacks {
    function onBuy(Obligation memory obligation, address borrower, uint256 assets, uint256 units, bytes memory data)
        external;
    function onSell(Obligation memory obligation, address borrower, uint256 assets, uint256 units, bytes memory data)
        external;
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external;
}
