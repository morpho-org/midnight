// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

interface IMakerCallbackDataRatifier is IRatifier {
    function RATIFIER() external view returns (address);
}
