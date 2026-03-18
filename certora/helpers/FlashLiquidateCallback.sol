// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";

interface IHavoc {
    function havoc() external;
}

contract FlashLiquidateCallback {
    // Tracks flashloans in obligation units (repaidUnits is already in units).
    function startFlashloan(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloan(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    // Tracks flashloans in obligation units by scaling token amounts by BALANCE_DECIMALS.
    // Used for regular flash loans where amount is in actual tokens.
    function startFlashloanTokens(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloanTokens(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function onLiquidate(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external {
        startFlashloan(obligation.loanToken, repaidUnits);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(obligation.loanToken, repaidUnits);
    }

    function onFlashLoan(address token, uint256 amount, bytes calldata data) external {
        startFlashloanTokens(token, amount);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloanTokens(token, amount);
    }
}
