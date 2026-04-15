// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract MulDiv {
    function mulDivUp(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return UtilsLib.mulDivUp(a, b, d);
    }

    function mulDivDown(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return UtilsLib.mulDivDown(a, b, d);
    }
}
