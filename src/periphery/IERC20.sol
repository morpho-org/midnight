// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IERC20 {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 shares) external returns (bool success);
    function transferFrom(address from, address to, uint256 shares) external returns (bool success);
    function approve(address spender, uint256 shares) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint256);
}
