// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {WhitelistEnterSubGate} from "./WhitelistEnterSubGate.sol";
import {IWhitelistEnterSubGateFactory} from "./interfaces/IWhitelistEnterSubGateFactory.sol";

contract WhitelistEnterSubGateFactory is IWhitelistEnterSubGateFactory {
    mapping(address subGate => bool) public isWhitelistEnterSubGate;

    function createWhitelistEnterSubGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address) {
        address subGate = address(
            new WhitelistEnterSubGate{salt: keccak256(abi.encode(preSalt, msg.sender))}(
                creditRoleSetter, debtRoleSetter, creditOpen, debtOpen
            )
        );
        isWhitelistEnterSubGate[subGate] = true;

        emit CreateWhitelistEnterSubGate(
            msg.sender, subGate, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        return subGate;
    }
}
