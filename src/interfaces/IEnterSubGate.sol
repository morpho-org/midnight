// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

/// @dev Market-specific permission checks for an enter gate. This interface cannot serve as IEnterGate.
interface IEnterSubGate {
    function canIncreaseCredit(bytes32 marketId, address account) external view returns (bool);
    function canIncreaseDebt(bytes32 marketId, address account) external view returns (bool);
}
