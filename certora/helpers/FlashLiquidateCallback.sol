// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market} from "../../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../../src/libraries/ConstantsLib.sol";

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
        bytes32,
        Market memory market,
        address,
        address,
        address,
        uint256,
        uint256,
        uint256 repaidUnits,
        uint256,
        bytes memory data
    ) external returns (bytes32) {
        startFlashloan(market.loanToken, repaidUnits);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(market.loanToken, repaidUnits);
        return CALLBACK_SUCCESS;
    }

    function onRepay(bytes32, Market memory market, address, uint256 units, bytes memory data)
        external
        returns (bytes32)
    {
        startFlashloan(market.loanToken, units);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(market.loanToken, units);
        return CALLBACK_SUCCESS;
    }

    function onFlashLoan(address, address[] calldata tokens, uint256[] calldata amounts, bytes calldata data)
        external
        returns (bytes32)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            startFlashloan(tokens[i], amounts[i]);
        }
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        for (uint256 i = 0; i < tokens.length; i++) {
            endFlashloan(tokens[i], amounts[i]);
        }
        return CALLBACK_SUCCESS;
    }
}
