// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IEcrecoverRatifier is IRatifier {
    /// ERRORS ///
    error InvalidProof();
    error InvalidSignature();
    error NotMidnight();
    error RootCanceled();
    error Unauthorized();

    /// EVENTS ///
    event CancelRoot(address indexed caller, address indexed maker, bytes32 indexed root);

    /// FUNCTIONS ///
    function cancelRoot(address maker, bytes32 root) external;

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function isRootCanceled(address maker, bytes32 root) external view returns (bool);
}
