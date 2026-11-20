// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IReceivableTokenFactory {
    // forgefmt: disable-start
    /// EVENTS ///
    event Constructor(address midnight);
    event CreateReceivableToken(address indexed owner, address indexed asset, bytes32 salt, address indexed newReceivableToken, string name, string symbol, address caller);

    /// FUNCTIONS ///
    function midnight() external view returns (address);
    function isReceivableToken(address account) external view returns (bool);
    function createReceivableToken(address owner, address asset, string memory name, string memory symbol, bytes32 salt) external returns (address newReceivableToken);
    // forgefmt: disable-end
}
