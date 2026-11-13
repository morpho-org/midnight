// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "../../../interfaces/IOracle.sol";

interface IReceivableToken is IERC20, IOracle {
    /// ERRORS ///
    error AlreadyMinted();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InsufficientCash();
    error InvalidProof();
    error InvalidSignature();
    error NotOwner();
    error RateTooHigh();
    error TransientBalanceNotSettled();

    // forgefmt: disable-start
    /// EVENTS ///
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Constructor(address indexed midnight, address indexed asset, address owner, string name, string symbol);
    event SetOwner(address indexed owner);
    event SetRoot(bytes32 indexed rootId, bytes32 root);
    event SetRate(uint256 rate);
    event Whitelist(address indexed account);
    event Mint(bytes32 indexed rootId, bytes32 indexed leaf, address indexed to, uint256 amount);
    event Redeem(address indexed caller, address indexed receiver, uint256 amount, uint256 assets);

    /// STORAGE GETTERS ///
    function midnight() external view returns (address);
    function asset() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint256);
    function owner() external view returns (address);
    function isWhitelisted(address account) external view returns (bool);
    function roots(bytes32 rootId) external view returns (bytes32);
    function minted(bytes32 leaf) external view returns (bool);
    function rate() external view returns (uint256);

    /// VIEW FUNCTIONS ///
    function totalSupply() external view returns (uint256);
    function transientSupply() external view returns (uint256);
    function cash() external view returns (uint256);

    /// FUNCTIONS ///
    function setOwner(address newOwner) external;
    function setRoot(bytes32 rootId, bytes32 newRoot) external;
    function setRate(uint256 newRate) external;
    function mint(
        bytes32 rootId,
        address key,
        uint256 reported,
        bytes32[] memory proof,
        address to,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function redeem(uint256 amount, address receiver) external returns (uint256 assets);
    // forgefmt: disable-end
}
