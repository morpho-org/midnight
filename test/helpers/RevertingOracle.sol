// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

contract RevertingOracle {
    uint256 internal _price = 1e36;
    bool internal stopped;

    function price() external view returns (uint256) {
        require(!stopped, "Oracle should not be called");
        return _price;
    }

    function stopOracle() external {
        stopped = true;
    }
}
