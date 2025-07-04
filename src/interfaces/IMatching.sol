// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./ITerms.sol";

interface IMatching {
    function take(Term memory term, uint256 assets, bytes calldata data) external returns (address);
}
