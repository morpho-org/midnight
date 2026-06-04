// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

interface ISetterRatifier is IRatifier {
    /// ERRORS ///
    error InvalidProof();
    error Unauthorized();
    error NotRatified();

    /// EVENTS ///
    event SetIsRootRatified(
        address indexed caller, address indexed maker, bytes32 indexed root, bool newIsRootRatified
    );

    /// FUNCTIONS ///
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external;

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function isRootRatified(address maker, bytes32 root) external view returns (bool);
}
