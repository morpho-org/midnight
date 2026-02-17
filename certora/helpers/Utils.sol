// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMorphoV2.sol";
import {IdLib} from "../../src/libraries/IdLib.sol";

contract Utils {
    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) external pure returns (bytes32) {
        return keccak256(IdLib.creationCode(obligation, chainId, morphoV2));
    }

    function naiveId(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function naiveId2(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encode(address(1), obligation));
    }

    function naiveId3(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encode(address(1), abi.encode(obligation)));
    }

    function naiveId4(Obligation memory obligation) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(address(1), abi.encode(obligation)));
    }
}
