// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IBuyCallback, IBuyerAssetsBound} from "../../../interfaces/ICallbacks.sol";

interface IBlueSwapBuyCallback is IBuyCallback, IBuyerAssetsBound {
    /// ERRORS ///
    error InvalidSwapCallback();
    error NotMidnight();
    error NotOwner();
    error NotOwnerBuyer();

    /// EVENTS ///
    /// @dev To track authorization changes, listen to the SetAuthorization event emitted by Blue.
    event Skim(address indexed caller, address indexed token, uint256 assets);
    /// @dev Emitted for every buy, including zero buys. swapper is zero when no swap is needed.
    event OnBuy(
        address indexed caller, bytes32 indexed id, uint256 buyerAssets, uint256 sourceAssets, address indexed swapper
    );

    /// STORAGE GETTERS ///
    function OWNER() external view returns (address);
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);

    /// FUNCTIONS ///
    function setAuthorization(address authorized, bool newIsAuthorized) external;
    function skim(address token) external;
}
