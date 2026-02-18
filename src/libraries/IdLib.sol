// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Creation code that deploys data as runtime bytecode.
    /// @dev Explanation of the prefix:
    /// hex       opcode          stack              comments
    /// ------------------------------------------------------------------------------
    /// 60 0b     PUSH1 0x0b      [11]               11 = len(prefix)
    /// 38        CODESIZE        [codesize, 11]
    /// 03        SUB             [len]              with len = codesize - 11
    /// 80        DUP1            [len, len]
    /// 60 0b     PUSH1 0x0b      [11, len, len]     code offset = 11
    /// 5f        PUSH0           [0, 11, len, len]  mem offset = 0
    /// 39        CODECOPY        [len]              mem[0:len] <- code[11:11+len]
    /// 5f        PUSH0           [0, len]           return offset = 0
    /// f3        RETURN          []                 return mem[0:len]
    function creationCode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"600b380380600b5f395ff3", data);
    }

    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(uint8(0xff), morphoV2, bytes32(chainId), keccak256(creationCode(abi.encode(obligation))))
        );
    }

    function codeIsCreated(bytes memory data, uint256 chainId, address morphoV2) internal view returns (bool, bytes32) {
        bytes32 id = keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(chainId), keccak256(creationCode(data))));
        bool created = address(uint160(uint256(id))).code.length > 0;
        return (created, id);
    }

    function toObligation(bytes32 id) internal view returns (Obligation memory) {
        return abi.decode(address(uint160(uint256(id))).code, (Obligation));
    }

    /// @dev Deploys a contract with runtime code data.
    /// @dev The contract code begins with 0x00 (STOP), because the first word is the offset of the obligation.
    function createCode(bytes memory data) internal {
        bytes memory _creationCode = creationCode(data);
        address create2Address;
        assembly ("memory-safe") {
            create2Address := create2(0, add(_creationCode, 0x20), mload(_creationCode), chainid())
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }
}
