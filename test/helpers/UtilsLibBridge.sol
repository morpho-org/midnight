// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";

/// @dev Test-only adapter. `UtilsLib.hashOffer` and `UtilsLib.isLeaf` take their struct/array
/// arguments as `calldata`, so test code holding `Offer memory` / `bytes32[] memory` cannot call
/// them directly. This bridge exposes external entry points that re-encode the args through
/// the calldata boundary so memory-typed callers can route through it.
contract UtilsLibBridge {
    function hashOffer(Offer calldata offer) external pure returns (bytes32) {
        return UtilsLib.hashOffer(offer);
    }

    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] calldata proof) external pure returns (bool) {
        return UtilsLib.isLeaf(root, leafHash, proof);
    }
}
