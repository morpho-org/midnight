// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Used as a prefix to some data, to give a creation code that deploys the data as runtime bytecode.
    /// @dev Explanation of the prefix:
    /// hex       opcode          stack              comments
    /// ------------------------------------------------------------------------------
    /// 60 0b     PUSH1 0x0b      [11]               11 = length(prefix)
    /// 38        CODESIZE        [codesize, 11]
    /// 03        SUB             [len]              with len = codesize - 11
    /// 80        DUP1            [len, len]
    /// 60 0b     PUSH1 0x0b      [11, len, len]     code offset = 11
    /// 5f        PUSH0           [0, 11, len, len]  mem offset = 0
    /// 39        CODECOPY        [len]              mem[0:len] <- code[11:11+len]
    /// 5f        PUSH0           [0, len]           return offset = 0
    /// f3        RETURN          []                 mem[0:len] is returned
    bytes constant SSTORE2_PREFIX = hex"600b380380600b5f395ff3";

    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes20) {
        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                uint8(0xff), morphoV2, chainId, keccak256(abi.encodePacked(SSTORE2_PREFIX, abi.encode(obligation)))
            )
        );
        // forge-lint: disable-next-line(unsafe-typecast) unsafe casting made on purpose.
        return bytes20(uint160(uint256(create2Hash)));
    }

    /// @dev Attempts to decode the data at address(id) into an obligation.
    function toObligation(bytes20 id) internal view returns (Obligation memory) {
        return abi.decode(address(id).code, (Obligation));
    }

    /// @dev Stores the data in the code of the contract at the given address.
    /// @dev Uses the chain id as salt.
    function storeInCode(Obligation memory obligation) internal returns (address create2Address) {
        bytes memory creationCode = abi.encodePacked(SSTORE2_PREFIX, abi.encode(obligation));
        assembly ("memory-safe") {
            create2Address := create2(0, add(creationCode, 0x20), mload(creationCode), chainid())
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }
}
