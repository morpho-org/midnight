// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IBuyCallback, IBuyerAssetsBound} from "../../../interfaces/ICallbacks.sol";
import {Authorization, Signature} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IBlueBuyCallback is IBuyCallback, IBuyerAssetsBound {
    /// ERRORS ///
    error AuthorizationExpired();
    error InconsistentLoanToken();
    error InvalidNonce();
    error InvalidSignature();
    error NotMidnight();
    error NotOwner();
    error NotOwnerBuyer();

    /// EVENTS ///
    /// @dev To track authorization changes, listen to the SetAuthorization event emitted by Blue.
    event SetAuthorizationWithSig(address indexed caller, uint256 nonce);
    event Skim(address indexed caller, address indexed token, uint256 assets);

    /// STORAGE GETTERS ///
    function OWNER() external view returns (address);
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function nonce() external view returns (uint256);

    /// FUNCTIONS ///
    function setAuthorization(address authorized, bool newIsAuthorized) external;
    function setAuthorizationWithSig(Authorization memory authorization, Signature memory signature) external;
    function skim(address token) external;
}
