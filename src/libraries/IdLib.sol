// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Collateral} from "../interfaces/IMorphoV2.sol";
import {IMorphoV2} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Calls its deployer with its 74:end bytes.
    /// @dev Uses the returned bytes as runtime code.
    /// @dev Explanation of the prefix:
    /// hex     opcode           stack                               comments
    /// -----------------------------------------------------------------------------------------------
    /// 60 4a   PUSH1 0x4a      [74]                                74 = len(prefix+chainId+morphoV2)
    /// 38      codeSize        [codeSize, 74]
    /// 80      DUP1            [codeSize, codeSize, 74]
    /// 91      SWAP2           [74, codeSize, codeSize]
    /// 5f      PUSH0           [0, 74, codeSize, codeSize]
    /// 39      CODECOPY        [codeSize]                          mem[0:codeSize] <- code[74:], zero-padded
    /// 5f      PUSH0           [0, codeSize]
    /// 5f      PUSH0           [0, 0, codeSize]
    /// 91      SWAP2           [codeSize, 0, 0]
    /// 5f      PUSH0           [0, codeSize, 0, 0]
    /// 33      CALLER          [caller, 0, codeSize, 0, 0]
    /// 5a      GAS             [gas, caller, 0, codeSize, 0, 0]
    /// fa      STATICCALL      [ok]
    /// 3d      RETURNDATASIZE  [returnDataSize, ok]
    /// 02      MUL             [retSize]                           0 if failed staticcall
    /// 80      DUP1            [retSize, retSize]
    /// 5f      PUSH0           [0, retSize, retSize]
    /// 5f      PUSH0           [0, 0, retSize, retSize]
    /// 3e      RETURNDATACOPY  [retSize]                           mem[0:retSize] <- returndata[0:retSize]
    /// 5f      PUSH0           [0, retSize]
    /// f3      RETURN          []                                  return mem[0:retSize]
    function creationCode(Obligation memory obligation, uint256 chainId, address morphoV2)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory prefix = hex"604a3880915f395f5f915f335afa3d02805f5f3e5ff3";
        return abi.encodePacked(prefix, chainId, morphoV2, IMorphoV2.packObligation.selector, abi.encode(obligation));
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
            address loanToken;
            uint256 maturity;
            uint8 len;
            assembly ("memory-safe") {
                let ptr := add(data, 32)
                loanToken := shr(96, mload(add(ptr, 1)))
                maturity := shr(208, mload(add(ptr, 21)))
                len := shr(248, mload(add(ptr, 27)))
            }

            obligation.loanToken = loanToken;
            obligation.maturity = maturity;

            Collateral[] memory collaterals = new Collateral[](len);

            for (uint256 i = 0; i < len; i++) {
                uint256 offset = 28 + i * 48;
                address token;
                uint256 lltv;
                address oracle;
                assembly ("memory-safe") {
                    let ptr := add(add(data, 32), offset)
                    token := shr(96, mload(ptr))
                    lltv := shr(192, mload(add(ptr, 20)))
                    oracle := shr(96, mload(add(ptr, 28)))
                }
                collaterals[i] = Collateral({token: token, lltv: lltv, oracle: oracle});
            }

            obligation.collaterals = collaterals;
        }
    }
}
