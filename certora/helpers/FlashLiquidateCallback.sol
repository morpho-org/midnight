// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMorphoV2.sol";

interface IHavoc {
    function havoc() external;
}

contract FlashLiquidateCallback {
    function startFlashloan(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloan(address token, uint256 amount) internal {
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
        startFlashloan(token, amount);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(token, amount);
    }
}
