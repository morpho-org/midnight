// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

interface IMidnightMulticall {
    function multicall(bytes[] calldata calls) external;
}

contract TakeCallbackReenter {
    function reenter(bytes calldata data) external {
        if (data.length == 0) return;

        bytes[] memory calls = abi.decode(data, (bytes[]));
        IMidnightMulticall(msg.sender).multicall(calls);
    }
}
