// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IOracle {
    function price() external view returns (uint256);
}
