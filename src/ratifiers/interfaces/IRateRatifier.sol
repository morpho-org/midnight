// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

bytes32 constant RATE_OFFER_TYPEHASH = 0xed54e2140d5ca64e1396a19e05c32707e2802af9a43570e408073f0b6843cfbb;

interface IRateRatifier is IRatifier {
    /// ERRORS ///
    error InvalidSignature();
    error NotMidnight();
    error Unauthorized();
    error WorsePrice();

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
}
