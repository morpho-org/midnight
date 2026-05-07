// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";
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
        Obligation memory obligation,
        uint256,
        uint256,
        uint256 repaidUnits,
        address,
        bytes memory data
    ) external returns (bytes32) {
        startFlashloan(obligation.loanToken, repaidUnits);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(obligation.loanToken, repaidUnits);
        return CALLBACK_SUCCESS;
    }

    function onRepay(bytes32, Obligation memory obligation, uint256 units, address, bytes memory data)
        external
        returns (bytes32)
    {
        startFlashloan(obligation.loanToken, units);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(obligation.loanToken, units);
        return CALLBACK_SUCCESS;
    }

    function onFlashLoan(address[] calldata tokens, uint256[] calldata amounts, bytes calldata data)
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
