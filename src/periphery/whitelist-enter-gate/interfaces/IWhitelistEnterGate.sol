// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

enum Side {
    Credit,
    Debt
}

enum Mode {
    Whitelist,
    Blacklist,
    Open
}

/// @dev keccak256("SetIsListed(address whitelister,uint8 side,address account,bool newIsListed,uint256 nonce,uint256
/// deadline)").
bytes32 constant SET_IS_LISTED_TYPEHASH = 0x761697b4bb3c847ca7ed6903857940d476bbe86e62ebdf82d2c8e867e65150ad;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IWhitelistEnterGate is IEnterGate {
    /// ERRORS ///
    error Abdicated();
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetMode(Side indexed side, Mode newMode);
    event SetIsWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsListed(address indexed whitelister, Side indexed side, address indexed account, bool newIsListed);
    event SetIsListedWithSig(address indexed whitelister, Side indexed side, address indexed account, bool newIsListed);

    /// STORAGE GETTERS ///
    function roleSetter() external view returns (address);
    function mode(Side side) external view returns (Mode);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isListed(Side side, address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setMode(Side side, Mode newMode) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsListed(Side side, address account, bool newIsListed) external;
    function setIsListedWithSig(
        address whitelister,
        Side side,
        address account,
        bool newIsListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
