// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IWhitelistEnterSubGateFactory {
    /// EVENTS ///
    event CreateWhitelistEnterSubGate(
        address indexed caller,
        address indexed subGate,
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    );

    /// STORAGE GETTERS ///
    function isWhitelistEnterSubGate(address subGate) external view returns (bool);

    /// FUNCTIONS ///
    function createWhitelistEnterSubGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address);
}
