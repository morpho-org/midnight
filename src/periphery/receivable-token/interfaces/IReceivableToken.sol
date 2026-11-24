// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";
import {ILiquidateCallback} from "../../../interfaces/ICallbacks.sol";

interface IReceivableToken is IERC20, ILiquidateCallback {
    /// ERRORS ///
    error ExceedsReceivables();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InsufficientCash();
    error InvalidLiquidation();
    error InvalidProof();
    error NotMidnight();
    error NotOwner();
    error NotWhitelisted();

    // forgefmt: disable-start
    /// EVENTS ///
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Constructor(address indexed midnight, address indexed asset, address owner, string name, string symbol, uint8 decimals, bytes32 root);
    event Whitelist(address indexed account);
    event Mint(address indexed account, uint256 amount, uint256 reported);
    event Redeem(address indexed caller, address indexed receiver, uint256 amount);
    event RedeemSeized(address indexed caller, bytes32 indexed id, address indexed borrower, uint256 amount, uint256 repaidUnits);

    /// STORAGE GETTERS ///
    function midnight() external view returns (address);
    function asset() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint256);
    function owner() external view returns (address);
    function isWhitelisted(address account) external view returns (bool);
    function root() external view returns (bytes32);
    function minted(address account) external view returns (uint256);

    /// VIEW FUNCTIONS ///
    function totalSupply() external view returns (uint256);
    function cash() external view returns (uint256);

    /// FUNCTIONS ///
    function whitelist(address account) external;
    function mint(uint256 amount, uint256 reported, bytes32[] memory proof) external;
    function redeem(uint256 amount, address receiver) external;
    // forgefmt: disable-end
}
