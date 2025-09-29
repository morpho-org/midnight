// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {Term} from "./ITerms.sol";

interface ICallbacks {
    function onTake(Term memory term, address borrower, uint256 assets, bytes memory data) external;
    function onLiquidate(
        bool seizeCollaterals,
        uint256[] memory amounts,
        address borrower,
        address liquidator,
        bytes memory data
    ) external;
}
