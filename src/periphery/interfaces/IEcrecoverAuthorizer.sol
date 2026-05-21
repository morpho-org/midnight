// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

/// @dev keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256
/// deadline)").
bytes32 constant AUTHORIZATION_TYPEHASH = 0x81d0284fb0e2cde18d0553b06189d6f7613c96a01bb5b5e7828eade6a0dcac91;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IEcrecoverAuthorizer {
    /// ERRORS ///
    error Expired();
    error InvalidNonce();
    error InvalidSignature();
    error Unauthorized();

    /// EVENTS ///
    event SetIsAuthorized(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized, uint256 nonce
    );

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function nonce(address authorizer) external view returns (uint256);

    /// FUNCTIONS ///
    function setIsAuthorized(Authorization memory authorization, Signature memory signature) external;
}
