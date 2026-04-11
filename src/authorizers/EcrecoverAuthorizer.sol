// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight} from "../interfaces/IMidnight.sol";
import {Authorization, Signature, AUTHORIZATION_TYPEHASH, EIP712_DOMAIN_TYPEHASH} from "../interfaces/IEcrecover.sol";

event SetIsAuthorized(
    address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized, uint256 nonce
);

contract EcrecoverAuthorizer {
    address public immutable MIDNIGHT;
    mapping(address => uint256) public nonce;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function setIsAuthorized(Authorization memory authorization, Signature calldata signature) external {
        require(block.timestamp <= authorization.deadline, "expired");
        require(authorization.nonce == nonce[authorization.authorizer]++, "invalid nonce");

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signer = ecrecover(digest, signature.v, signature.r, signature.s);
        require(
            signer != address(0)
                && (signer == authorization.authorizer
                    || IMidnight(MIDNIGHT).isAuthorized(authorization.authorizer, signer)),
            "invalid signature"
        );

        emit SetIsAuthorized(
            msg.sender,
            authorization.authorizer,
            authorization.authorized,
            authorization.isAuthorized,
            authorization.nonce
        );

        IMidnight(MIDNIGHT)
            .setIsAuthorized(authorization.authorizer, authorization.authorized, authorization.isAuthorized);
    }
}
