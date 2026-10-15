// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterSubGate} from "../../../interfaces/IEnterSubGate.sol";

/// @dev keccak256("SetIsWhitelisted(bytes32 marketId,bool creditSide,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)").
bytes32 constant SET_IS_WHITELISTED_TYPEHASH = 0x03332143ba0ae522faefd74cec6be3aeffbcb872c5d82f2ed6db1bb9005b559c;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IWhitelistEnterSubGate is IEnterSubGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error InvalidNonce();
    error NotRoleSetter();
    error NotWhitelister();
    error WhitelistedStatusChanged();

    /// EVENTS ///
    event Constructor(address indexed creditRoleSetter, address indexed debtRoleSetter, bool creditOpen, bool debtOpen);
    event SetRoleSetter(bool creditSide, address indexed newRoleSetter);
    event SetIsWhitelister(bool creditSide, address indexed account, bool newIsWhitelister);
    event SetIsWhitelisted(
        address indexed whitelister,
        bytes32 indexed marketId,
        bool creditSide,
        address indexed account,
        bool newIsWhitelisted
    );
    event SetIsWhitelistedWithSig(
        address caller,
        address indexed whitelister,
        bytes32 indexed marketId,
        bool creditSide,
        address indexed account,
        bool newIsWhitelisted,
        uint256 signatureNonce,
        uint256 previousNonce
    );

    /// STORAGE GETTERS ///
    function CREDIT_OPEN() external view returns (bool);
    function DEBT_OPEN() external view returns (bool);
    function roleSetter(bool creditSide) external view returns (address);
    function isWhitelister(bool creditSide, address account) external view returns (bool);
    function nonces(bytes32 marketId, bool creditSide, address whitelister, address account)
        external
        view
        returns (uint256);
    function isWhitelisted(bytes32 marketId, bool creditSide, address account) external view returns (bool);

    /// SETTERS ///
    function setRoleSetter(bool creditSide, address newRoleSetter) external;
    function setIsWhitelister(bool creditSide, address account, bool newIsWhitelister) external;
    function setIsWhitelisted(bytes32 marketId, bool creditSide, address account, bool newIsWhitelisted) external;
    function setIsWhitelistedWithSig(
        bytes32 marketId,
        bool creditSide,
        address account,
        bool newIsWhitelisted,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// GETTERS ///
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// MULTICALL ///
    function multicall(bytes[] calldata data) external;
}
