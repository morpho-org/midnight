// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

interface IEcrecoverRatifier is IRatifier {
    /// ERRORS ///
    error InvalidSignature();
    error Unauthorized();

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
}
