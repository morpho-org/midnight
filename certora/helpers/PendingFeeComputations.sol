// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

contract PendingFeeComputations {
    using UtilsLib for uint256;

    function subtractProportionalUp(uint256 pendingFee, uint256 credit, uint256 newCredit)
        external
        pure
        returns (uint256)
    {
        return pendingFee - pendingFee.mulDivUp(credit - newCredit, credit);
    }

    function scaleDown(uint256 pendingFee, uint256 credit, uint256 newCredit) external pure returns (uint256) {
        return pendingFee.mulDivDown(newCredit, credit);
    }
}
