// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IBlueBuyCallbackFactory {
    /// ERRORS ///
    error AlreadyCreated();

    /// EVENTS ///
    event CreateBlueBuyCallback(address indexed owner, address callback);

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function callbackOf(address owner) external view returns (address);
    function isBlueCallback(address callback) external view returns (bool);

    /// FUNCTIONS ///
    function createBlueBuyCallback(address owner) external;
}
