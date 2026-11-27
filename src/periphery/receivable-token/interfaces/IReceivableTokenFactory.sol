// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @dev keccak256("CreateReceivableToken(address owner,address asset,string name,string symbol,bytes32 root,uint256 nonce)").
bytes32 constant CREATE_RECEIVABLE_TOKEN_TYPEHASH = 0x6ebdd48556e623f8c6db8e8b3b8d7036d147dd697fdbe9215cd0439dc8d1bbf6;

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IReceivableTokenFactory {
    /// ERRORS ///
    error InvalidNonce();
    error InvalidSignature();

    // forgefmt: disable-start
    /// EVENTS ///
    event Constructor(address midnight);
    event CreateReceivableToken(address indexed signer, address indexed asset, address indexed newReceivableToken, address owner, string name, string symbol, bytes32 root, uint256 nonce, address caller);

    /// FUNCTIONS ///
    function midnight() external view returns (address);
    function isReceivableToken(address account) external view returns (bool);
    function nonces(address signer) external view returns (uint256);
    function createReceivableToken(address signer, address owner, address asset, string memory name, string memory symbol, bytes32 root, uint256 nonce, Signature memory signature) external returns (address newReceivableToken);
    // forgefmt: disable-end
}
