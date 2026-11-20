// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {SafeTransferLib} from "../../src/libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract MockExchange {
    uint256 public rate;

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        SafeTransferLib.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        SafeTransferLib.safeTransfer(tokenOut, msg.sender, UtilsLib.mulDivDown(amountIn, rate, ORACLE_PRICE_SCALE));
    }
}
