// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

interface IEcrecoverRatifier is IRatifier {
    /// ERRORS ///
    error InvalidProof();
    error InvalidSignature();
    error NotMidnight();
    error Unauthorized();

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
}
