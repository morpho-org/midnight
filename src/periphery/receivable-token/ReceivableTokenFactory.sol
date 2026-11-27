// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {ReceivableToken} from "./ReceivableToken.sol";
import {
    IReceivableTokenFactory,
    Signature,
    CREATE_RECEIVABLE_TOKEN_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IReceivableTokenFactory.sol";

/// @dev Deploys `ReceivableToken`s from EIP-712 signed parameters with per-signer sequential nonces.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed deployments are no longer valid.
contract ReceivableTokenFactory is IReceivableTokenFactory {
    address public immutable midnight;

    mapping(address account => bool) public isReceivableToken;
    mapping(address signer => uint256) public nonces;

    constructor(address _midnight) {
        midnight = _midnight;
        emit Constructor(_midnight);
    }

    /// @dev Verifies an EIP-712 signature from `signer`, consumes `nonces[signer]`, and deploys a `ReceivableToken`.
    /// @dev Returns the address of the deployed ReceivableToken.
    function createReceivableToken(
        address signer,
        address owner,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 root,
        uint256 nonce,
        Signature calldata signature
    ) external returns (address) {
        require(nonce == nonces[signer]++, InvalidNonce());

        bytes32 hashStruct = keccak256(
            abi.encode(
                CREATE_RECEIVABLE_TOKEN_TYPEHASH,
                owner,
                asset,
                keccak256(bytes(name)),
                keccak256(bytes(symbol)),
                root,
                nonce
            )
        );
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, signature.v, signature.r, signature.s);
        require(recovered != address(0) && recovered == signer, InvalidSignature());

        bytes32 salt = keccak256(abi.encode(signer, nonce));
        address newReceivableToken =
            address(new ReceivableToken{salt: salt}(midnight, asset, owner, signer, name, symbol, root));

        isReceivableToken[newReceivableToken] = true;
        emit CreateReceivableToken(signer, asset, newReceivableToken, owner, name, symbol, root, nonce, msg.sender);

        return newReceivableToken;
    }
}
