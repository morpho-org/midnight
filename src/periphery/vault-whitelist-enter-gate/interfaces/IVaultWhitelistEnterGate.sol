// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

/// @dev keccak256("SetIsWhitelisted(bool creditSide,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)").
bytes32 constant SET_IS_WHITELISTED_TYPEHASH = 0xa19ec4634ebb855ea0b75237f7a684a4cb96e8cdae8536e4128409e9ea8d4982;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IMidnightAdapterFactory {
    function midnight() external view returns (address);
    function isMidnightAdapter(address account) external view returns (bool);
}

interface IMidnightAdapter {
    function parentVault() external view returns (address);
}

interface IVault {
    function balanceOf(address account) external view returns (uint256);
}

interface IVaultWhitelistEnterGate is IEnterGate {
    /// ERRORS ///
    error AccountIsAdapter();
    error AdapterFactoryNotWhitelisted();
    error DeadlineExpired();
    error IncorrectEnterGate();
    error InvalidSigner();
    error InvalidNonce();
    error NoAdapterCredit();
    error NoVaultShares();
    error NotAdapter();
    error NotRoleSetter();
    error NotWhitelister();
    error WhitelistedStatusChanged();

    /// EVENTS ///
    event Constructor(address indexed creditRoleSetter, address indexed debtRoleSetter, bool creditOpen, bool debtOpen);
    event SetRoleSetter(bool creditSide, address indexed newRoleSetter);
    event SetIsWhitelister(bool creditSide, address indexed account, bool newIsWhitelister);
    event SetIsWhitelisted(
        address indexed whitelister, bool creditSide, address indexed account, bool newIsWhitelisted
    );
    event SetIsWhitelistedWithSig(
        address caller,
        address indexed whitelister,
        bool creditSide,
        address indexed account,
        bool newIsWhitelisted,
        uint256 signatureNonce,
        uint256 previousNonce
    );
    event AddWhitelistedAdapterFactory(address indexed adapterFactory);
    event TransientAllowIncreaseCredit(
        address indexed caller,
        address indexed account,
        address indexed adapterFactory,
        address adapter,
        bytes32 marketId
    );

    /// STORAGE GETTERS ///
    function CREDIT_OPEN() external view returns (bool);
    function DEBT_OPEN() external view returns (bool);
    function roleSetter(bool creditSide) external view returns (address);
    function isWhitelister(bool creditSide, address account) external view returns (bool);
    function nonces(bool creditSide, address whitelister, address account) external view returns (uint256);
    function isWhitelisted(bool creditSide, address account) external view returns (bool);
    function isWhitelistedAdapterFactory(address adapterFactory) external view returns (bool);

    /// SETTERS ///
    function setRoleSetter(bool creditSide, address newRoleSetter) external;
    function setIsWhitelister(bool creditSide, address account, bool newIsWhitelister) external;
    function setIsWhitelisted(bool creditSide, address account, bool newIsWhitelisted) external;
    function addWhitelistedAdapterFactory(address adapterFactory) external;
    function setIsWhitelistedWithSig(
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
    function transientAllowIncreaseCredit(address account, address adapterFactory, address adapter, bytes32 marketId)
        external;
    function isTransientlyAllowed(address account) external view returns (bool);

    /// MULTICALL ///
    function multicall(bytes[] calldata data) external;
}
