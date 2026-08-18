// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IBlueBuyCallbackFactory {
    /// EVENTS ///
    event CreateBlueBuyCallback(address indexed caller, address indexed owner, bytes32 salt, address callback);

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function callbackOf(address owner, bytes32 salt) external view returns (address);
    function isBlueBuyCallback(address callback) external view returns (bool);

    /// FUNCTIONS ///
    function createBlueBuyCallback(address owner, bytes32 salt) external returns (address);
}
