// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market} from "../../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../../src/libraries/ConstantsLib.sol";
import {ILiquidateCallback, IRepayCallback, IFlashLoanCallback} from "../../src/interfaces/ICallbacks.sol";

interface IHavoc {
    function havoc() external;
}

contract FlashLiquidateCallback is ILiquidateCallback, IRepayCallback, IFlashLoanCallback {
    function onLiquidate(
        address,
        bytes32,
        Market memory,
        uint256,
        uint256,
        uint256,
        address,
        address,
        bytes memory data,
        uint256
    ) external returns (bytes32) {
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        return CALLBACK_SUCCESS;
    }

    function onRepay(bytes32, Market memory, uint256, address, bytes memory data)
        external
        returns (bytes32)
    {
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        return CALLBACK_SUCCESS;
    }

    function onFlashLoan(address, address[] calldata, uint256[] calldata, bytes calldata data)
        external
        returns (bytes32)
    {
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        return CALLBACK_SUCCESS;
    }
}
