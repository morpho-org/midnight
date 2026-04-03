// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";

interface IHavoc {
    function performHavoc() external;
}

contract FlashTakeCallback {
    function startFlashloan(bytes32 obligationId, uint256 units) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloan(bytes32 obligationId, uint256 units) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function onBuy(bytes32 obligationId, Obligation memory, address, uint256, uint256 units, bytes memory data)
        external
    {
        startFlashloan(obligationId, units);
        address account = abi.decode(data, (address));
        IHavoc(account).performHavoc();
        endFlashloan(obligationId, units);
    }

    function onSell(bytes32 obligationId, Obligation memory, address, uint256, uint256 units, bytes memory data)
        external
    {
        startFlashloan(obligationId, units);
        address account = abi.decode(data, (address));
        IHavoc(account).performHavoc();
        endFlashloan(obligationId, units);
    }
}
