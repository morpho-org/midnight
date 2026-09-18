// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";

contract GenerateRoot {
    // Reference root for a non-empty, power-of-two list of offers.
    function generateRoot(Offer[] memory leaves) public pure returns (bytes32) {
        require(leaves.length > 0 && (leaves.length & (leaves.length - 1)) == 0, "invalid leaves length");

        bytes32[] memory level = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            level[i] = HashLib.hashOffer(leaves[i]);
        }

        uint256 levelLength = level.length;
        while (levelLength > 1) {
            levelLength /= 2;
            for (uint256 i = 0; i < levelLength; i++) {
                level[i] = HashLib.hashNode(level[2 * i], level[2 * i + 1]);
            }
        }

        return level[0];
    }
}
