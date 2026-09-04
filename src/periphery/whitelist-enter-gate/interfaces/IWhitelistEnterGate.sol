// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

enum Mode {
    Whitelist,
    Blacklist,
    Open
}

/// @dev keccak256("SetIsCreditListed(address whitelister,address account,bool newIsCreditListed,uint256 nonce,uint256
/// deadline)").
bytes32 constant SET_IS_CREDIT_LISTED_TYPEHASH = 0x9114d3606ad37255c43341c3824b562ebba2d2480fa55e46bbbd04401047d9f2;

/// @dev keccak256("SetIsDebtListed(address whitelister,address account,bool newIsDebtListed,uint256 nonce,uint256
/// deadline)").
bytes32 constant SET_IS_DEBT_LISTED_TYPEHASH = 0x8aaf134724517237f0ae092efda154d7d065b0a74593ac13f38d5a7b70c1ad33;

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
    event SetIsCreditListed(address indexed whitelister, address indexed account, bool newIsCreditListed);
    event SetIsDebtListed(address indexed whitelister, address indexed account, bool newIsDebtListed);
    event SetIsCreditListedWithSig(address indexed whitelister, address indexed account, bool newIsCreditListed);
    event SetIsDebtListedWithSig(address indexed whitelister, address indexed account, bool newIsDebtListed);

    /// STORAGE GETTERS ///
    function CREDIT_MODE() external view returns (Mode);
    function DEBT_MODE() external view returns (Mode);
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isCreditListed(address account) external view returns (bool);
    function isDebtListed(address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsCreditListed(address account, bool newIsCreditListed) external;
    function setIsDebtListed(address account, bool newIsDebtListed) external;
    function setIsCreditListedWithSig(
        address whitelister,
        address account,
        bool newIsCreditListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function setIsDebtListedWithSig(
        address whitelister,
        address account,
        bool newIsDebtListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
