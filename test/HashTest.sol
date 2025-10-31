// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {console} from "forge-std/console.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract HashTest is BaseTest {
    function testHashObligation() public pure {
        Obligation memory obligation;
        obligation.chainId = 9;
        obligation.loanToken = address(0x7);
        obligation.maturity = 3;
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(0x8), lltv: 10, oracle: address(0x9)});
        obligation.collaterals = collaterals;

        assertEq(UtilsLib.hashObligation(obligation), keccak256(abi.encode(obligation)));
    }
}
