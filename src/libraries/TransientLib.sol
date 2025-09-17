// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library TransientLib {
    bytes32 constant PREFIX = keccak256("transient");

    function setMapping(address borrower, bool val) internal {
        bytes32 slot = keccak256(abi.encodePacked(PREFIX, borrower));
        assembly {
            tstore(slot, val)
        }
    }

    function getMapping(address borrower) internal view returns (bool val) {
        bytes32 slot = keccak256(abi.encodePacked(PREFIX, borrower));
        assembly {
            val := tload(slot)
        }
    }
}
