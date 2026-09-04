// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

/// @dev keccak256("SetIsWhitelisted(address whitelister,address account,bool newIsWhitelisted,uint256 nonce,uint256
/// deadline)").
bytes32 constant SET_IS_WHITELISTED_TYPEHASH = 0x885e4103ed9e01f4b1d5697a5c6e973bde6ed5e1974431108fe8e7c9473a7b81;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IWhitelistEnterGate is IEnterGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsWhitelisted(address indexed whitelister, address indexed account, bool newIsWhitelisted);
    event SetIsWhitelistedWithSig(address indexed whitelister, address indexed account, bool newIsWhitelisted);

    /// STORAGE GETTERS ///
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isWhitelisted(address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsWhitelisted(address account, bool newIsWhitelisted) external;
    function setIsWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
