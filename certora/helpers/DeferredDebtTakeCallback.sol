// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";

interface IHavoc2 {
    function performHavoc() external;
}

contract DeferredDebtTakeCallback {
    function startDeferredDebt(bytes32 obligationId, uint256 units) internal {
        obligationId;
        units;
        // Dummy function to insert the deferred debt logic in the spec.
    }

    function endDeferredDebt(bytes32 obligationId, uint256 units) internal {
        obligationId;
        units;
        // Dummy function to insert the deferred debt logic in the spec.
    }

    function onBuy(bytes32 obligationId, Obligation memory, address, uint256, uint256 units, bytes memory data) external {
        startDeferredDebt(obligationId, units);
        address account = abi.decode(data, (address));
        IHavoc2(account).performHavoc();
        endDeferredDebt(obligationId, units);
    }

    function onSell(bytes32 obligationId, Obligation memory, address, uint256, uint256 units, bytes memory data)
        external
    {
        startDeferredDebt(obligationId, units);
        address account = abi.decode(data, (address));
        IHavoc2(account).performHavoc();
        endDeferredDebt(obligationId, units);
    }
}
