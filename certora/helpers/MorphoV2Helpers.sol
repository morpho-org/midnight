// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MorphoV2, Obligation} from "../../src/MorphoV2.sol";

contract MorphoV2Helpers is MorphoV2 {
    function balanceOf(address token, address account) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    function id(Obligation memory obligation) external pure returns (bytes32) {
        return _id(obligation);
    }
}
