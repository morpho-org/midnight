// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IBuyCallback} from "../../interfaces/ICallbacks.sol";
import {Market} from "../../interfaces/IMidnight.sol";
import {Authorization, Signature} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IBlueBuyCallback is IBuyCallback {
    /// ERRORS ///
    error ApproveReturnedFalse();
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

    /// STORAGE GETTERS ///
    function OWNER() external view returns (address);
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function nonce() external view returns (uint256);

    /// FUNCTIONS ///
    function maxBuyerAssets(
        bytes32 id,
        Market memory market,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external view returns (uint256);
    function setAuthorization(address authorized, bool newIsAuthorized) external;
    function setAuthorizationWithSig(Authorization memory authorization, Signature memory signature) external;
}
