// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Signature} from "../../src/interfaces/IMidnight.sol";

contract AuthHelper {
    function encodeRatificationData(bytes32 root, bytes32[] calldata proof, Signature memory s)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(root, proof, s);
    }
}
