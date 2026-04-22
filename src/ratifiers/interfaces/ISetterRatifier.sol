// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

interface ISetterRatifier is IRatifier {
    /// ERRORS ///
    error Unauthorized();
    error NotRatified();

    /// EVENTS ///
    event SetIsRatified(address indexed maker, bytes32 indexed root, bool newApproval);

    /// FUNCTIONS ///
    function setIsRatified(address maker, bytes32 root, bool newIsRatified) external;

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function isRatified(address maker, bytes32 root) external view returns (bool);
}
