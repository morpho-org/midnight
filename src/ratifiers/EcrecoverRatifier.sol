// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IEcrecoverRatifier} from "./interfaces/IEcrecoverRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../interfaces/IEcrecover.sol";
import {SignatureLib} from "../libraries/SignatureLib.sol";

contract EcrecoverRatifier is IEcrecoverRatifier {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }
    bytes constant COLLATERAL_PARAMS_TYPE =
        "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
    bytes constant OBLIGATION_TYPE =
        "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
    bytes constant OFFER_TYPE =
        "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";

    function onRatify(Offer memory offer, bytes32 root, bytes memory ratifierData) external view returns (bytes32) {
        (Signature memory sig, uint256 height) = abi.decode(ratifierData, (Signature, uint256));
        bytes32 structHash = keccak256(abi.encode(SignatureLib.rootTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address _signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == offer.maker || IMidnight(MIDNIGHT).isAuthorized(offer.maker, _signer), Unauthorized());
        return CALLBACK_SUCCESS;
    }
}
