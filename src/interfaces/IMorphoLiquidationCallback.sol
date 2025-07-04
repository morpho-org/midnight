// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {Seizure} from "./ITerms.sol";

interface IMorphoLiquidationCallback {
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external;
}
