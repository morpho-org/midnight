// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IWhitelistEnterGate,
    Side,
    Mode,
    SET_IS_LISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IWhitelistEnterGate.sol";

/// @dev Using this gate allows to restrict who can increase their credit or debt in a market.
/// @dev Each side (credit, debt) has its own list and its own mode: whitelist (only listed accounts can enter),
/// blacklist (only unlisted accounts can enter) or open (any account can enter).
/// @dev Both sides start in whitelist mode. Switching a side to open is irreversible.
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are
/// no longer valid.
contract WhitelistEnterGate is IWhitelistEnterGate {
    address public roleSetter;
    mapping(Side side => Mode) public mode;
    mapping(address account => bool) public isWhitelister;
    mapping(address whitelister => mapping(address account => uint256)) public nonces;
    mapping(Side side => mapping(address account => bool)) public isListed;

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
        return canIncrease(Side.Credit, account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return canIncrease(Side.Debt, account);
    }

    function canIncrease(Side side, address account) internal view returns (bool) {
        Mode sideMode = mode[side];
        if (sideMode == Mode.Open) return true;
        return isListed[side][account] == (sideMode == Mode.Whitelist);
    }

    function setRoleSetter(address newRoleSetter) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        roleSetter = newRoleSetter;
        emit SetRoleSetter(newRoleSetter);
    }

    function setMode(Side side, Mode newMode) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        require(mode[side] != Mode.Open, Abdicated());
        mode[side] = newMode;
        emit SetMode(side, newMode);
    }

    function setIsWhitelister(address account, bool newIsWhitelister) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        isWhitelister[account] = newIsWhitelister;
        emit SetIsWhitelister(account, newIsWhitelister);
    }

    function setIsListed(Side side, address account, bool newIsListed) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isListed[side][account] = newIsListed;
        emit SetIsListed(msg.sender, side, account, newIsListed);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsListed with the take, without requiring a transaction from the whitelister.
    function setIsListedWithSig(
        address whitelister,
        Side side,
        address account,
        bool newIsListed,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_LISTED_TYPEHASH,
                whitelister,
                side,
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
        isListed[side][account] = newIsListed;
        emit SetIsListedWithSig(recovered, side, account, newIsListed);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
