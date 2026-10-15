// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {VaultWhitelistEnterGate} from "./VaultWhitelistEnterGate.sol";
import {IVaultWhitelistEnterGateFactory} from "./interfaces/IVaultWhitelistEnterGateFactory.sol";

contract VaultWhitelistEnterGateFactory is IVaultWhitelistEnterGateFactory {
    mapping(address gate => bool) public isVaultWhitelistEnterGate;

    function createVaultWhitelistEnterGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address) {
        address gate = address(
            new VaultWhitelistEnterGate{salt: keccak256(abi.encode(preSalt, msg.sender))}(
                creditRoleSetter, debtRoleSetter, creditOpen, debtOpen
            )
        );
        isVaultWhitelistEnterGate[gate] = true;

        emit CreateVaultWhitelistEnterGate(
            msg.sender, gate, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        return gate;
    }
}
