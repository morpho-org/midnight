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

        bytes memory encoded = abi.encode(obligation);
        for(uint256 i = 32; i <= encoded.length; i+=32) {
            bytes32 value;
            assembly {
                value := mload(add(encoded, i))
            }
            console.logBytes32(value);
        }
        console.log("--------------------------------");

        assertEq(UtilsLib.hashObligation(obligation), keccak256(abi.encode(obligation)));
        // assertEq(UtilsLib.hashObligation2(obligation), keccak256(abi.encode(obligation)));
        uint256 length = 32 * 6 + 3 * 32 * obligation.collaterals.length;
        for(uint256 i; i < length; i+=32) {
            bytes32 value;
            assembly {
                value := mload(add(obligation, i))
            }
            console.logBytes32(value);
        }
    }
}
