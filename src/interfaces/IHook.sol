// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./ITerms.sol";

interface IHook {
    function hook(Term memory term, address owner, uint256 assets, uint256 bonds, bytes calldata)
        external
        returns (bytes32);
}
