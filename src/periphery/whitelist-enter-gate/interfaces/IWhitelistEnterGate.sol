// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

/// @dev keccak256("SetIsWhitelisted(address whitelister,bool creditSide,address account,bool newIsWhitelisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_WHITELISTED_TYPEHASH = 0xafcd80c394b848db7e286546e6489c656b2de05d7187f276e11c4212d9a5e6b7;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

/// @dev keccak256("SetIsGloballyWhitelisted(address whitelister,address account,bool newIsWhitelisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_GLOBALLY_WHITELISTED_TYPEHASH =
    0x4daac07d57fa17382e34128b5db66891ba0e253f04952d56b8e376b48a67be9f;

interface IWhitelistEnterGate is IEnterGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter, bool creditOpen, bool debtOpen);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsGlobalWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsWhitelister(bool creditSide, address indexed account, bool newIsWhitelister);
    event SetIsGloballyWhitelisted(address indexed whitelister, address indexed account, bool newIsWhitelisted);
    event SetIsWhitelisted(
        address indexed whitelister, bool creditSide, address indexed account, bool newIsWhitelisted
    );
    event SetIsGloballyWhitelistedWithSig(address indexed whitelister, address indexed account, bool newIsWhitelisted);
    event SetIsWhitelistedWithSig(
        address indexed whitelister, bool creditSide, address indexed account, bool newIsWhitelisted
    );

    /// STORAGE GETTERS ///
    function CREDIT_OPEN() external view returns (bool);
    function DEBT_OPEN() external view returns (bool);
    function roleSetter() external view returns (address);
    function isGlobalWhitelister(address account) external view returns (bool);
    function isWhitelister(bool creditSide, address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isGloballyWhitelisted(address account) external view returns (bool);
    function isWhitelisted(bool creditSide, address account) external view returns (bool);

    /// SETTERS ///
    function setRoleSetter(address newRoleSetter) external;
    function setIsGlobalWhitelister(address account, bool newIsWhitelister) external;
    function setIsWhitelister(bool creditSide, address account, bool newIsWhitelister) external;
    function setIsGloballyWhitelisted(address account, bool newIsWhitelisted) external;
    function setIsWhitelisted(bool creditSide, address account, bool newIsWhitelisted) external;
    function setIsGloballyWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function setIsWhitelistedWithSig(
        address whitelister,
        bool creditSide,
        address account,
        bool newIsWhitelisted,
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
