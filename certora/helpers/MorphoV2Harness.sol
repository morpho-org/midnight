// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {MorphoV2} from "../../src/MorphoV2.sol";
import {FeeLib} from "../../src/libraries/FeeLib.sol";

contract MorphoV2Harness is MorphoV2 {
    constructor() MorphoV2() {}

    function getObligationTradingFee(bytes32 id, uint256 index) public view returns (uint256) {
        uint256 feeStorage = _obligationTradingFeeStorage[id];

        return FeeLib.getFee(feeStorage, index);
    }

    function getDefaultTradingFee(address loanToken, uint256 index) public view returns (uint256) {
        uint256 feeStorage = _defaultTradingFeeStorage[loanToken];

        return FeeLib.getFee(feeStorage, index);
    }
}
