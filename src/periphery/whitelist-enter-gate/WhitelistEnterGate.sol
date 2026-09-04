// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IWhitelistEnterGate,
    Mode,
    SET_IS_CREDIT_WHITELISTED_TYPEHASH,
    SET_IS_CREDIT_BLACKLISTED_TYPEHASH,
    SET_IS_DEBT_WHITELISTED_TYPEHASH,
    SET_IS_DEBT_BLACKLISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IWhitelistEnterGate.sol";

/// @dev Using this gate allows to restrict who can increase their credit or debt in a market.
/// @dev Each side (credit, debt) has its own whitelist, its own blacklist and its own mode, fixed at deployment:
/// whitelist (only whitelisted accounts can enter), blacklist (only non-blacklisted accounts can enter) or open (any
/// account can enter). Only the list matching the mode is read.
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are
/// no longer valid.
contract WhitelistEnterGate is IWhitelistEnterGate {
    Mode public immutable CREDIT_MODE;
    Mode public immutable DEBT_MODE;

    address public roleSetter;
    mapping(address account => bool) public isWhitelister;
    mapping(address whitelister => mapping(address account => uint256)) public nonces;
    mapping(address account => bool) public isCreditWhitelisted;
    mapping(address account => bool) public isCreditBlacklisted;
    mapping(address account => bool) public isDebtWhitelisted;
    mapping(address account => bool) public isDebtBlacklisted;

    constructor(address _roleSetter, Mode _creditMode, Mode _debtMode) {
        CREDIT_MODE = _creditMode;
        DEBT_MODE = _debtMode;
        roleSetter = _roleSetter;
        emit Constructor(_roleSetter, _creditMode, _debtMode);
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
        if (CREDIT_MODE == Mode.Open) return true;
        if (CREDIT_MODE == Mode.Whitelist) return isCreditWhitelisted[account];
        return !isCreditBlacklisted[account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        if (DEBT_MODE == Mode.Open) return true;
        if (DEBT_MODE == Mode.Whitelist) return isDebtWhitelisted[account];
        return !isDebtBlacklisted[account];
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

    function setIsCreditWhitelisted(address account, bool newIsCreditWhitelisted) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isCreditWhitelisted[account] = newIsCreditWhitelisted;
        emit SetIsCreditWhitelisted(msg.sender, account, newIsCreditWhitelisted);
    }

    function setIsCreditBlacklisted(address account, bool newIsCreditBlacklisted) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isCreditBlacklisted[account] = newIsCreditBlacklisted;
        emit SetIsCreditBlacklisted(msg.sender, account, newIsCreditBlacklisted);
    }

    function setIsDebtWhitelisted(address account, bool newIsDebtWhitelisted) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isDebtWhitelisted[account] = newIsDebtWhitelisted;
        emit SetIsDebtWhitelisted(msg.sender, account, newIsDebtWhitelisted);
    }

    function setIsDebtBlacklisted(address account, bool newIsDebtBlacklisted) external {
        require(isWhitelister[msg.sender], NotWhitelister());
        isDebtBlacklisted[account] = newIsDebtBlacklisted;
        emit SetIsDebtBlacklisted(msg.sender, account, newIsDebtBlacklisted);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsCreditWhitelisted with the take, without requiring a transaction from the whitelister.
    function setIsCreditWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsCreditWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_CREDIT_WHITELISTED_TYPEHASH,
                whitelister,
                account,
                newIsCreditWhitelisted,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isCreditWhitelisted[account] = newIsCreditWhitelisted;
        emit SetIsCreditWhitelistedWithSig(recovered, account, newIsCreditWhitelisted);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsCreditBlacklisted with the take, without requiring a transaction from the whitelister.
    function setIsCreditBlacklistedWithSig(
        address whitelister,
        address account,
        bool newIsCreditBlacklisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_CREDIT_BLACKLISTED_TYPEHASH,
                whitelister,
                account,
                newIsCreditBlacklisted,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isCreditBlacklisted[account] = newIsCreditBlacklisted;
        emit SetIsCreditBlacklistedWithSig(recovered, account, newIsCreditBlacklisted);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsDebtWhitelisted with the take, without requiring a transaction from the whitelister.
    function setIsDebtWhitelistedWithSig(
        address whitelister,
        address account,
        bool newIsDebtWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_DEBT_WHITELISTED_TYPEHASH,
                whitelister,
                account,
                newIsDebtWhitelisted,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isDebtWhitelisted[account] = newIsDebtWhitelisted;
        emit SetIsDebtWhitelistedWithSig(recovered, account, newIsDebtWhitelisted);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsDebtBlacklisted with the take, without requiring a transaction from the whitelister.
    function setIsDebtBlacklistedWithSig(
        address whitelister,
        address account,
        bool newIsDebtBlacklisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_DEBT_BLACKLISTED_TYPEHASH,
                whitelister,
                account,
                newIsDebtBlacklisted,
                nonces[whitelister][account]++,
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister && isWhitelister[recovered], InvalidSigner());
        isDebtBlacklisted[account] = newIsDebtBlacklisted;
        emit SetIsDebtBlacklistedWithSig(recovered, account, newIsDebtBlacklisted);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
