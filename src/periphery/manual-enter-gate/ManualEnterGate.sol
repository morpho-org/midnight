// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IManualEnterGate, SET_IS_LISTED_TYPEHASH, EIP712_DOMAIN_TYPEHASH} from "./interfaces/IManualEnterGate.sol";

/// @dev Using this gate allows to restrict who can increase their credit or debt in a market.
/// @dev Each side (credit, debt) has its own whitelist, stored in a single mapping keyed by side. Only listed accounts
/// can enter on that side.
/// @dev The role setter can abdicate a side, which permanently freezes its list.
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are
/// no longer valid.
contract ManualEnterGate is IManualEnterGate {
    address public roleSetter;
    mapping(address account => bool) public isWhitelister;
    mapping(address whitelister => mapping(address account => uint256)) public nonces;
    mapping(bool creditSide => mapping(address account => bool)) public isListed;
    mapping(bool creditSide => bool) public abdicated;

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
        return isListed[true][account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return isListed[false][account];
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

    function setIsListed(bool creditSide, address account, bool newIsListed) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        require(!abdicated[creditSide], Abdicated());
        isListed[creditSide][account] = newIsListed;
        emit SetIsListed(msg.sender, creditSide, account, newIsListed);
    }

    /// @dev Allows to batch setIsListed with the take, without requiring a transaction from the whitelister.
    function setIsListedWithSig(
        address whitelister,
        bool creditSide,
        address account,
        bool newIsListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        require(!abdicated[creditSide], Abdicated());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_LISTED_TYPEHASH,
                whitelister,
                creditSide,
                account,
                newIsListed,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isListed[creditSide][account] = newIsListed;
        emit SetIsListedWithSig(recovered, creditSide, account, newIsListed);
    }

    /// @dev Permanently freezes the list of the given side.
    function abdicate(bool creditSide) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        abdicated[creditSide] = true;
        emit Abdicate(creditSide);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
