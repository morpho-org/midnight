// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

enum Mode {
    Whitelist,
    Blacklist,
    Open
}

/// @dev keccak256("SetIsListed(address whitelister,bool creditSide,address account,bool newIsListed,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_LISTED_TYPEHASH = 0xaac22fdd76cd855cfe3fa355b662b8549bdabbbdecefa623d35f34d97aa5d1d4;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IManualEnterGate is IEnterGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter, Mode creditMode, Mode debtMode);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsListed(address indexed whitelister, bool creditSide, address indexed account, bool newIsListed);
    event SetIsListedWithSig(address indexed whitelister, bool creditSide, address indexed account, bool newIsListed);

    /// STORAGE GETTERS ///
    function CREDIT_MODE() external view returns (Mode);
    function DEBT_MODE() external view returns (Mode);
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isListed(bool creditSide, address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsListed(bool creditSide, address account, bool newIsListed) external;
    function setIsListedWithSig(
        address whitelister,
        bool creditSide,
        address account,
        bool newIsListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
