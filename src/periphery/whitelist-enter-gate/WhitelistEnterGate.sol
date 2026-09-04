// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IWhitelistEnterGate,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IWhitelistEnterGate.sol";

/// @dev Using this gate allows to restrict who can increase their credit or debt in a market.
/// @dev As with any enter gate, it does not prevent accounts from exiting the market once they are un-whitelisted.
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are
/// no longer valid.
contract WhitelistEnterGate is IWhitelistEnterGate {
    address public roleSetter;
    mapping(address account => bool) public isWhitelister;
    mapping(address whitelister => mapping(address account => uint256)) public nonces;
    mapping(address account => bool) public isWhitelisted;

    constructor(address _roleSetter) {
        roleSetter = _roleSetter;
        emit Constructor(_roleSetter);
    }

    /// @dev Useful for EOAs to batch privileged calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do
    /// the multicall themselves.
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return isWhitelisted[account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return isWhitelisted[account];
    }

    function setRoleSetter(address newRoleSetter) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        roleSetter = newRoleSetter;
        emit SetRoleSetter(newRoleSetter);
    }

    function setIsWhitelister(address account, bool newIsWhitelister) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        isWhitelister[account] = newIsWhitelister;
        emit SetIsWhitelister(account, newIsWhitelister);
    }

    function setIsWhitelisted(address account, bool newIsWhitelisted) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isWhitelisted[account] = newIsWhitelisted;
        emit SetIsWhitelisted(msg.sender, account, newIsWhitelisted);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsWhitelisted with the take, without requiring a transaction from the whitelister.
    function setIsWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH,
                whitelister,
                account,
                newIsWhitelisted,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isWhitelisted[account] = newIsWhitelisted;
        emit SetIsWhitelistedWithSig(recovered, account, newIsWhitelisted);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
