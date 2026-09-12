// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

struct Ratification {
    bool isRatified;
    uint128 nonce;
}

/// @dev keccak256("SetIsRootRatified(address maker,bytes32 root,bool newIsRootRatified,uint128 nonce,uint256
/// deadline)").
bytes32 constant SET_IS_ROOT_RATIFIED_TYPEHASH = 0x90eef64d3dc1bb270295c48dc2b436bf38642d8089bea6374e8e612e17061bda;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface ISetterRateRatifier is IRatifier {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidNonce();
    error InvalidProof();
    error InvalidSignature();
    error NotRatified();
    error OfferExpired();
    error RatifiedStatusChanged();
    error Unauthorized();
    error UnauthorizedTaker();
    error WorsePrice();

    /// EVENTS ///
    event SetIsRootRatified(
        address indexed caller, address indexed maker, bytes32 indexed root, bool newIsRootRatified
    );
    event SetIsRootRatifiedWithSig(
        address indexed signer,
        address indexed maker,
        bytes32 indexed root,
        bool newIsRootRatified,
        uint128 nonce,
        uint128 currentNonce
    );

    /// FUNCTIONS ///
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external;
    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// GETTERS ///
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function isRootRatified(address maker, bytes32 root) external view returns (bool);
    function ratification(address maker, bytes32 root) external view returns (bool isRatified, uint128 nonce);
}
