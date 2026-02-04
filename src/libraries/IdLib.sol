// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Creation code that returns the code after the prefix as runtime bytecode, except for the first 52 bytes.
    /// @dev Explanation of the prefix:
    /// hex       opcode          stack              comments
    /// ------------------------------------------------------------------------------
    /// 60 3f     PUSH1 0x3f      [63]               63 = len(prefix+chainId+morphoV2)
    /// 38        CODESIZE        [codesize, 63]
    /// 03        SUB             [len]              with len = codesize - 63
    /// 80        DUP1            [len, len]
    /// 60 3f     PUSH1 0x3f      [63, len, len]     code offset = 63
    /// 5f        PUSH0           [0, 63, len, len]  mem offset = 0
    /// 39        CODECOPY        [len]              mem[0:len] <- code[63:63+len]
    /// 5f        PUSH0           [0, len]           return offset = 0
    /// f3        RETURN          []                 mem[0:len] is returned
    function creationCode(Obligation memory obligation, uint256 chainId, address morphoV2)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory prefix = hex"603f380380603f5f395ff3";
        return abi.encodePacked(prefix, chainId, morphoV2, abi.encode(obligation));
    }

    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes32) {
        return keccak256(creationCode(obligation, chainId, morphoV2));
    }

    function idToObligation(bytes32 id, address morphoV2) internal view returns (Obligation memory) {
        address create2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
        return abi.decode(create2Address.code, (Obligation));
    }

    /// @dev Deploys a contract with runtime code = abi.encode(obligation)
    /// @dev The contract code begins with 0x00 (STOP), because the first word is the offset of the obligation.
    function storeInCode(Obligation memory obligation) internal {
        bytes memory _creationCode = creationCode(obligation, block.chainid, address(this));
        address create2Address;
        assembly ("memory-safe") {
            create2Address := create2(0, add(_creationCode, 0x20), mload(_creationCode), 0)
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }
}
