// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../interfaces/IGate.sol";

/// @dev keccak256("SetIsWhitelisted(address whitelister,bool creditSide,address account,bool newIsWhitelisted,uint256
/// nonce,uint256 deadline)").
bytes32 constant SET_IS_WHITELISTED_TYPEHASH = 0xafcd80c394b848db7e286546e6489c656b2de05d7187f276e11c4212d9a5e6b7;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IManualEnterGate is IEnterGate {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidSigner();
    error NotRoleSetter();
    error NotWhitelister();

    /// EVENTS ///
    event Constructor(address indexed roleSetter, bool creditOpen, bool debtOpen);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsWhitelister(address indexed account, bool newIsWhitelister);
    event SetIsWhitelisted(
        address indexed whitelister, bool creditSide, address indexed account, bool newIsWhitelisted
    );
    event SetIsWhitelistedWithSig(
        address indexed whitelister, bool creditSide, address indexed account, bool newIsWhitelisted
    );

    /// STORAGE GETTERS ///
    function CREDIT_OPEN() external view returns (bool);
    function DEBT_OPEN() external view returns (bool);
    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address whitelister, address account) external view returns (uint256);
    function isWhitelisted(bool creditSide, address account) external view returns (bool);

    /// FUNCTIONS ///
    function multicall(bytes[] calldata data) external;
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsWhitelisted(bool creditSide, address account, bool newIsWhitelisted) external;
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
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
