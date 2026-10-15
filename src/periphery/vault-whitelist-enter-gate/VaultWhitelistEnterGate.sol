// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IVaultWhitelistEnterGate,
    IMidnightAdapter,
    IMidnightAdapterFactory,
    IVault,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IVaultWhitelistEnterGate.sol";
import {IMidnight} from "../../interfaces/IMidnight.sol";

/// @dev This gate can restrict which accounts can increase their credit or debt in a market.
/// @dev Each side (credit, debt) has its own whitelist. Only whitelisted accounts can enter on that side.
/// @dev Each side has its own role setter and whitelisters.
/// @dev A side can be made open at deployment, letting any account enter on that side (forever).
/// @dev The credit role setter can add adapter factories, but never remove them.
/// @dev Anyone can transiently allow an account to increase credit until the end of the transaction if it holds shares of the parent vault of an adapter of a whitelisted factory that has credit in a market using this gate.
/// @dev The allowance holds for every market using this gate.
/// @dev Whitelisted factories are trusted for their midnight() and isMidnightAdapter() responses.
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are no longer valid.
contract VaultWhitelistEnterGate is IVaultWhitelistEnterGate {
    /// STORAGE ///
    bool public immutable CREDIT_OPEN;
    bool public immutable DEBT_OPEN;

    mapping(bool creditSide => address) public roleSetter;
    mapping(bool creditSide => mapping(address account => bool)) public isWhitelister;
    mapping(bool creditSide => mapping(address whitelister => mapping(address account => uint256))) public nonces;
    mapping(bool creditSide => mapping(address account => bool)) public isWhitelisted;
    mapping(address adapterFactory => bool) public isWhitelistedAdapterFactory;

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

    function setIsWhitelisted(bool creditSide, address account, bool newIsWhitelisted) external {
        require(isWhitelister[creditSide][msg.sender], NotWhitelister());
        isWhitelisted[creditSide][account] = newIsWhitelisted;
        emit SetIsWhitelisted(msg.sender, creditSide, account, newIsWhitelisted);
    }

    function addWhitelistedAdapterFactory(address adapterFactory) external {
        require(msg.sender == roleSetter[true], NotRoleSetter());
        isWhitelistedAdapterFactory[adapterFactory] = true;
        emit AddWhitelistedAdapterFactory(adapterFactory);
    }

    /// @dev Allows to batch setIsWhitelisted with the take, without requiring a transaction from the whitelister.
    function setIsWhitelistedWithSig(
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
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, creditSide, account, newIsWhitelisted, nonce, deadline));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address whitelister = ecrecover(digest, v, r, s);
        require(whitelister != address(0) && isWhitelister[creditSide][whitelister], InvalidSigner());
        uint256 previousNonce = nonces[creditSide][whitelister][account];
        if (nonce == previousNonce) {
            nonces[creditSide][whitelister][account] = previousNonce + 1;
            isWhitelisted[creditSide][account] = newIsWhitelisted;
        } else {
            require(nonce < previousNonce, InvalidNonce());
            require(isWhitelisted[creditSide][account] == newIsWhitelisted, WhitelistedStatusChanged());
        }
        emit SetIsWhitelistedWithSig(
            msg.sender, whitelister, creditSide, account, newIsWhitelisted, nonce, previousNonce
        );
    }

    /// GETTERS ///

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function transientAllowIncreaseCredit(address account, address adapterFactory, address adapter, bytes32 marketId)
        external
    {
        require(isWhitelistedAdapterFactory[adapterFactory], AdapterFactoryNotWhitelisted());
        require(IMidnightAdapterFactory(adapterFactory).isMidnightAdapter(adapter), NotAdapter());
        require(!IMidnightAdapterFactory(adapterFactory).isMidnightAdapter(account), AccountIsAdapter());

        address midnight = IMidnightAdapterFactory(adapterFactory).midnight();
        require(IMidnight(midnight).toMarket(marketId).enterGate == address(this), IncorrectEnterGate());
        require(IMidnight(midnight).credit(marketId, adapter) > 0, NoAdapterCredit());
        require(IVault(IMidnightAdapter(adapter).parentVault()).balanceOf(account) > 0, NoVaultShares());

        bytes32 slot = keccak256(abi.encode(account));
        assembly ("memory-safe") {
            tstore(slot, 1)
        }
        emit TransientAllowIncreaseCredit(msg.sender, account, adapterFactory, adapter, marketId);
    }

    function isTransientlyAllowed(address account) public view returns (bool allowed) {
        bytes32 slot = keccak256(abi.encode(account));
        assembly ("memory-safe") {
            allowed := tload(slot)
        }
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return CREDIT_OPEN || isWhitelisted[true][account] || isTransientlyAllowed(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return DEBT_OPEN || isWhitelisted[false][account];
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
