// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {WhitelistEnterGate} from "./WhitelistEnterGate.sol";
import {IWhitelistEnterGateFactory} from "./interfaces/IWhitelistEnterGateFactory.sol";

contract WhitelistEnterGateFactory is IWhitelistEnterGateFactory {
    mapping(address gate => bool) public isWhitelistEnterGate;

    function createWhitelistEnterGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address) {
        address gate = address(
            new WhitelistEnterGate{salt: keccak256(abi.encode(preSalt, msg.sender))}(
                creditRoleSetter, debtRoleSetter, creditOpen, debtOpen
            )
        );
        isWhitelistEnterGate[gate] = true;

        emit CreateWhitelistEnterGate(msg.sender, gate, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen, preSalt);
        return gate;
    }
}
