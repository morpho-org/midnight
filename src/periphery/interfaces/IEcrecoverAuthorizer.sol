// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Authorization, Signature} from "../../interfaces/IEcrecover.sol";

interface IEcrecoverAuthorizer {
    /// ERRORS ///
    error Expired();
    error InvalidNonce();
    error InvalidSignature();

    /// EVENTS ///
    event SetIsAuthorized(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized, uint256 nonce
    );

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function nonce(address authorizer) external view returns (uint256);

    /// FUNCTIONS ///
    function setIsAuthorized(Authorization memory authorization, Signature calldata signature) external;
}
