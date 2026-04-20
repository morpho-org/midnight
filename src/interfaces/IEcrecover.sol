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

bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorized,bool isAuthorized,uint256 nonce,uint256 deadline)");
bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
bytes constant OBLIGATION_TYPE =
    "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
bytes constant OFFER_TYPE =
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";
