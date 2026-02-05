// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Collateral} from "../interfaces/IMorphoV2.sol";

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
        return abi.encodePacked(prefix, chainId, morphoV2, pack(obligation));
    }

    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes32) {
        return keccak256(creationCode(obligation, chainId, morphoV2));
    }

    function idToObligation(bytes32 id, address morphoV2) internal view returns (Obligation memory) {
        address create2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
        return unpack(create2Address.code);
    }

    /// @dev Deploys a contract with runtime code = pack(obligation)
    /// @dev The contract code begins with 0x00 (STOP) for safety.
    function storeInCode(Obligation memory obligation) internal {
        bytes memory _creationCode = creationCode(obligation, block.chainid, address(this));
        address create2Address;
        assembly ("memory-safe") {
            create2Address := create2(0, add(_creationCode, 0x20), mload(_creationCode), 0)
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }

    /// @dev Returns a packed representation of the obligation.
    /// @dev The maturity must fit on 6 bytes.
    /// @dev The collateral count must fit on 1 byte.
    /// @dev All lltvs must fit on 8 bytes.
    function pack(Obligation memory obligation) internal pure returns (bytes memory result) {
        require(obligation.maturity <= type(uint48).max, "maturity too large");
        require(obligation.collaterals.length <= type(uint8).max, "collateral count too large");

        result = abi.encodePacked(
            bytes1(0x00), obligation.loanToken, uint48(obligation.maturity), uint8(obligation.collaterals.length)
        );

        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            Collateral memory collateral = obligation.collaterals[i];
            require(collateral.lltv <= type(uint64).max, "lltv too large");
            result = abi.encodePacked(result, collateral.token, uint64(collateral.lltv), collateral.oracle);
        }
    }

    function unpack(bytes memory data) internal pure returns (Obligation memory obligation) {
        require(data.length > 0, "empty data");
        unchecked {
            obligation.loanToken = address(uint160(get(data, 1) >> 96));
            obligation.maturity = uint48(get(data, 21) >> 208);
            uint8 len = uint8(data[27]);

            obligation.collaterals = new Collateral[](len);

            for (uint256 i = 0; i < len; i++) {
                uint256 offset = 28 + i * 48;
                obligation.collaterals[i].token = address(uint160(get(data, offset) >> 96));
                obligation.collaterals[i].lltv = uint64(get(data, offset + 20) >> 192);
                obligation.collaterals[i].oracle = address(uint160(get(data, offset + 28) >> 96));
            }
        }
    }

    function get(bytes memory data, uint256 offset) private pure returns (uint256 w) {
        assembly ("memory-safe") {
            w := mload(add(add(data, 32), offset))
        }
    }
}
