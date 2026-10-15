// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IWhitelistEnterSubGate,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IWhitelistEnterSubGate.sol";

/// @dev This subgate restricts which accounts can increase their credit or debt in each market.
/// @dev Each side (credit, debt) has its own whitelist per market. Only whitelisted accounts can enter on that side.
/// @dev Each side has its own role setter and whitelisters, shared across markets.
/// @dev A side can be made open at deployment, letting any account enter on that side in all markets (forever).
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev Use this contract through an enter gate. It does not implement Midnight's gate interface.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are no longer valid.
contract WhitelistEnterSubGate is IWhitelistEnterSubGate {
    /// STORAGE ///
    bool public immutable CREDIT_OPEN;
    bool public immutable DEBT_OPEN;

    mapping(bool creditSide => address) public roleSetter;
    mapping(bool creditSide => mapping(address account => bool)) public isWhitelister;
    mapping(
        bytes32 marketId
            => mapping(bool creditSide => mapping(address whitelister => mapping(address account => uint256)))
    ) public nonces;
    mapping(bytes32 marketId => mapping(bool creditSide => mapping(address account => bool))) public isWhitelisted;

    /// CONSTRUCTOR ///

    constructor(address _creditRoleSetter, address _debtRoleSetter, bool _creditOpen, bool _debtOpen) {
        roleSetter[true] = _creditRoleSetter;
        roleSetter[false] = _debtRoleSetter;
        CREDIT_OPEN = _creditOpen;
        DEBT_OPEN = _debtOpen;
        emit Constructor(_creditRoleSetter, _debtRoleSetter, _creditOpen, _debtOpen);
    }

    /// SETTERS ///

    function setRoleSetter(bool creditSide, address newRoleSetter) external {
        require(msg.sender == roleSetter[creditSide], NotRoleSetter());
        roleSetter[creditSide] = newRoleSetter;
        emit SetRoleSetter(creditSide, newRoleSetter);
    }

    function setIsWhitelister(bool creditSide, address account, bool newIsWhitelister) external {
        require(msg.sender == roleSetter[creditSide], NotRoleSetter());
        isWhitelister[creditSide][account] = newIsWhitelister;
        emit SetIsWhitelister(creditSide, account, newIsWhitelister);
    }

    function setIsWhitelisted(bytes32 marketId, bool creditSide, address account, bool newIsWhitelisted) external {
        require(isWhitelister[creditSide][msg.sender], NotWhitelister());
        isWhitelisted[marketId][creditSide][account] = newIsWhitelisted;
        emit SetIsWhitelisted(msg.sender, marketId, creditSide, account, newIsWhitelisted);
    }

    /// @dev Allows to batch setIsWhitelisted with the take, without requiring a transaction from the whitelister.
    function setIsWhitelistedWithSig(
        bytes32 marketId,
        bool creditSide,
        address account,
        bool newIsWhitelisted,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(SET_IS_WHITELISTED_TYPEHASH, marketId, creditSide, account, newIsWhitelisted, nonce, deadline)
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address whitelister = ecrecover(digest, v, r, s);
        require(whitelister != address(0) && isWhitelister[creditSide][whitelister], InvalidSigner());
        uint256 previousNonce = nonces[marketId][creditSide][whitelister][account];
        if (nonce == previousNonce) {
            nonces[marketId][creditSide][whitelister][account] = previousNonce + 1;
            isWhitelisted[marketId][creditSide][account] = newIsWhitelisted;
        } else {
            require(nonce < previousNonce, InvalidNonce());
            require(isWhitelisted[marketId][creditSide][account] == newIsWhitelisted, WhitelistedStatusChanged());
        }
        emit SetIsWhitelistedWithSig(
            msg.sender, whitelister, marketId, creditSide, account, newIsWhitelisted, nonce, previousNonce
        );
    }

    /// GETTERS ///

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function canIncreaseCredit(bytes32 marketId, address account) external view returns (bool) {
        return CREDIT_OPEN || isWhitelisted[marketId][true][account];
    }

    function canIncreaseDebt(bytes32 marketId, address account) external view returns (bool) {
        return DEBT_OPEN || isWhitelisted[marketId][false][account];
    }

    /// MULTICALL ///

    /// @dev Useful for EOAs to batch privileged calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do the multicall themselves.
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
}
