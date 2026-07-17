// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IBuyCallback} from "../../interfaces/ICallbacks.sol";

interface IBlueBuyCallback is IBuyCallback {
    /// ERRORS ///
    error ApproveReturnedFalse();
    error InconsistentLoanToken();
    error NotMidnight();
    error NotOwnerBuyer();

    /// STORAGE GETTERS ///
    function OWNER() external view returns (address);
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
}
