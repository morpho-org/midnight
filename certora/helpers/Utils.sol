// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";
import {IdLib} from "../../src/libraries/IdLib.sol";

contract Utils {
    function hashObligation(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }
}
