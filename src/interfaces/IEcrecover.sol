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

bytes32 constant AUTHORIZATION_TYPEHASH = 0x81d0284fb0e2cde18d0553b06189d6f7613c96a01bb5b5e7828eade6a0dcac91;
bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
bytes32 constant OBLIGATION_TYPEHASH = 0x9a433cf47bf8ba35aebb7c021b48c098de91d2acf046171894f31a9e58809cad;
bytes32 constant OFFER_TYPEHASH = 0xcde81aa026ac33a64ecbe0eb2e4e6609c1a9324c12902b576d4edd3241a4c0af;
