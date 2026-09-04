// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

enum Mode {
    Whitelist,
    Blacklist,
    Open
}

/// @dev keccak256("SetIsCreditWhitelisted(address whitelister,address account,bool newIsCreditWhitelisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_CREDIT_WHITELISTED_TYPEHASH =
    0x88afb43a6cf611de86504c35265db171a5f4de965a5f54871c12227dd6fbd94c;

/// @dev keccak256("SetIsCreditBlacklisted(address whitelister,address account,bool newIsCreditBlacklisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_CREDIT_BLACKLISTED_TYPEHASH =
    0x785f1b1ff93e57210f5c4b05ddc54690e668b1df33ef2578850672fcfde5c232;

/// @dev keccak256("SetIsDebtWhitelisted(address whitelister,address account,bool newIsDebtWhitelisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_DEBT_WHITELISTED_TYPEHASH = 0x004b4938a923070f671a6b54bbbc1e154302657dec852dd7f2a4e2c0769cd787;

/// @dev keccak256("SetIsDebtBlacklisted(address whitelister,address account,bool newIsDebtBlacklisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_DEBT_BLACKLISTED_TYPEHASH = 0xb042fdfb40e53c6f2e0d441610e764c5b1447669dd7bddfa15723bc61ccdaf7e;

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
    event SetIsCreditWhitelisted(address indexed whitelister, address indexed account, bool newIsCreditWhitelisted);
    event SetIsCreditBlacklisted(address indexed whitelister, address indexed account, bool newIsCreditBlacklisted);
    event SetIsDebtWhitelisted(address indexed whitelister, address indexed account, bool newIsDebtWhitelisted);
    event SetIsDebtBlacklisted(address indexed whitelister, address indexed account, bool newIsDebtBlacklisted);
    event SetIsCreditWhitelistedWithSig(
        address indexed whitelister, address indexed account, bool newIsCreditWhitelisted
    );
    event SetIsCreditBlacklistedWithSig(
        address indexed whitelister, address indexed account, bool newIsCreditBlacklisted
    );
    event SetIsDebtWhitelistedWithSig(address indexed whitelister, address indexed account, bool newIsDebtWhitelisted);
    event SetIsDebtBlacklistedWithSig(address indexed whitelister, address indexed account, bool newIsDebtBlacklisted);

    /// STORAGE GETTERS ///
    function CREDIT_MODE() external view returns (Mode);
    function DEBT_MODE() external view returns (Mode);
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isCreditWhitelisted(address account) external view returns (bool);
    function isCreditBlacklisted(address account) external view returns (bool);
    function isDebtWhitelisted(address account) external view returns (bool);
    function isDebtBlacklisted(address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsCreditWhitelisted(address account, bool newIsCreditWhitelisted) external;
    function setIsCreditBlacklisted(address account, bool newIsCreditBlacklisted) external;
    function setIsDebtWhitelisted(address account, bool newIsDebtWhitelisted) external;
    function setIsDebtBlacklisted(address account, bool newIsDebtBlacklisted) external;
    function setIsCreditWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsCreditWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function setIsCreditBlacklistedWithSig(
        address whitelister,
        address account,
        bool newIsCreditBlacklisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function setIsDebtWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsDebtWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function setIsDebtBlacklistedWithSig(
        address whitelister,
        address account,
        bool newIsDebtBlacklisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
