// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IWhitelistEnterGateFactory {
    /// EVENTS ///
    event CreateWhitelistEnterGate(
        address indexed caller,
        address indexed gate,
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 salt
    );

    /// STORAGE GETTERS ///
    function isWhitelistEnterGate(address gate) external view returns (bool);

    /// FUNCTIONS ///
    function createWhitelistEnterGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 salt
    ) external returns (address);
}
