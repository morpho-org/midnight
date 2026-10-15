// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IEnterGateFactory {
    function isGate(address account, bytes32 marketId) external view returns (bool);
}
