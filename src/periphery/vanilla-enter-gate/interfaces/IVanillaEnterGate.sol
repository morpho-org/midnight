// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

enum Mode {
    Whitelist,
    Blacklist,
    Open
}

/// @dev keccak256("SetIsListed(address whitelister,address account,bool newIsListed,uint256 nonce,uint256 deadline)").
bytes32 constant SET_IS_LISTED_TYPEHASH = 0x985236ac386509ed0a8f60bf731439f038fd6f3d7a4da28f0802af8d80965809;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IWhitelistEnterGate is IEnterGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter, Mode creditMode, Mode debtMode);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsListed(address indexed whitelister, address indexed account, bool newIsListed);
    event SetIsListedWithSig(address indexed whitelister, address indexed account, bool newIsListed);

    /// STORAGE GETTERS ///
    function CREDIT_MODE() external view returns (Mode);
    function DEBT_MODE() external view returns (Mode);
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isListed(address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsListed(address account, bool newIsListed) external;
    function setIsListedWithSig(
        address whitelister,
        address account,
        bool newIsListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
