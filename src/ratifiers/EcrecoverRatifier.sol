// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IEcrecoverRatifier} from "./interfaces/IEcrecoverRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "../interfaces/IEcrecover.sol";

contract EcrecoverRatifier is IEcrecoverRatifier {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function onRatify(Offer memory offer, bytes32 root, bytes memory data) external view returns (bytes32) {
        Signature memory sig = abi.decode(data, (Signature));
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address _signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == offer.maker || IMidnight(MIDNIGHT).isAuthorized(offer.maker, _signer), Unauthorized());
        return CALLBACK_SUCCESS;
    }
}
