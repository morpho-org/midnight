// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, Id, MarketParams, Authorization, Signature} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {AUTHORIZATION_TYPEHASH, DOMAIN_TYPEHASH} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {Market} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {IBlueBuyCallback} from "./interfaces/IBlueBuyCallback.sol";

interface IERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @dev Anyone authorized by the owner on Midnight can pull from the Blue position held by this callback contract by
/// making the owner buy dummy credit on Midnight.
contract BlueBuyCallback is IBlueBuyCallback {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    address public immutable OWNER;
    address public immutable MIDNIGHT;
    address public immutable BLUE;
    uint256 public nonce;

    constructor(address _owner, address _midnight, address _blue) {
        OWNER = _owner;
        MIDNIGHT = _midnight;
        BLUE = _blue;

        IMorpho(BLUE).setAuthorization(OWNER, true);
    }

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        require(msg.sender == OWNER, NotOwner());
        if (IMorpho(BLUE).isAuthorized(address(this), authorized) != newIsAuthorized) {
            IMorpho(BLUE).setAuthorization(authorized, newIsAuthorized);
        }
    }

    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature) external {
        require(block.timestamp <= authorization.deadline, AuthorizationExpired());
        require(authorization.nonce == nonce++, InvalidNonce());

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signer = ecrecover(digest, signature.v, signature.r, signature.s);
        require(signer != address(0) && signer == authorization.authorizer && signer == OWNER, InvalidSignature());

        emit SetAuthorizationWithSig(msg.sender, authorization.nonce);
        if (IMorpho(BLUE).isAuthorized(address(this), authorization.authorized) != authorization.isAuthorized) {
            IMorpho(BLUE).setAuthorization(authorization.authorized, authorization.isAuthorized);
        }
    }

    /// @dev Reverts if the owner position on the requested market is too small or if the liquidity on that market is
    /// too small.
    function onBuy(
        bytes32,
        Market memory market,
        uint256 buyerAssets,
        uint256,
        uint256,
        address buyer,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        require(buyer == OWNER, NotOwnerBuyer());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(marketParams.loanToken == market.loanToken, InconsistentLoanToken());

        if (buyerAssets > 0) IMorpho(BLUE).withdraw(marketParams, buyerAssets, 0, address(this), address(this));
        forceApproveMax(market.loanToken, MIDNIGHT);

        return CALLBACK_SUCCESS;
    }

    function buyerAssetsBound(bytes32, Market memory market, address buyer, bytes memory data)
        external
        view
        returns (uint256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));

        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
            IMorpho(BLUE).expectedMarketBalances(marketParams);
        uint256 supplyAssets = IMorpho(BLUE).position(marketParams.id(), address(this)).supplyShares
            .toAssetsDown(totalSupplyAssets, totalSupplyShares);
        uint256 liquidity = totalSupplyAssets - totalBorrowAssets;

        return supplyAssets < liquidity ? supplyAssets : liquidity;
    }

    /// @dev Skips the approval entirely to save gas when the current allowance is already at least 2^95 - 1 (some
    /// tokens like COMP and UNI on Ethereum have a max allowance of type(uint96).max).
    /// @dev Resets to 0 before re-approving to support USDT-like tokens.
    function forceApproveMax(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) >= type(uint96).max / 2) return;
        safeApprove(token, spender, 0);
        safeApprove(token, spender, type(uint256).max);
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ApproveReturnedFalse());
    }
}
