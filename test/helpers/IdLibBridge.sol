// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";
import {IdLib} from "../../src/libraries/IdLib.sol";

/// @dev Test-only adapter. `IdLib` helpers take their `Obligation` argument as `calldata`,
/// so test code holding `Obligation memory` cannot call them directly. This bridge exposes
/// external entry points that re-encode the args through the calldata boundary so memory-typed
/// callers can route through it.
contract IdLibBridge {
    function toId(Obligation calldata obligation, uint256 chainId, address midnight) external pure returns (bytes32) {
        return IdLib.toId(obligation, chainId, midnight);
    }

    function storeInCode(Obligation calldata obligation, uint256 chainId) external returns (address) {
        return IdLib.storeInCode(obligation, chainId);
    }
}
