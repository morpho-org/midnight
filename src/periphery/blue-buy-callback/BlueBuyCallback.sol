// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, Id, MarketParams, Authorization, Signature} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {AUTHORIZATION_TYPEHASH, DOMAIN_TYPEHASH} from "../../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "../../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {Market} from "../../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../../libraries/ConstantsLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {IBlueBuyCallback} from "./interfaces/IBlueBuyCallback.sol";
import {IERC20Extended} from "./interfaces/IERC20Extended.sol";
import {ERC20Lib} from "../libraries/ERC20Lib.sol";

/// @dev This contract is meant to be used as a Midnight buy offer callback in order to park funds on a Blue market
/// while the offer waits to be taken.
/// @dev The positions on the Blue markets are acquired through supplies on behalf of this contract (permissionless).
/// @dev The OWNER can withdraw this position on Blue, for example if the offer expired.
/// @dev The OWNER can also authorize other accounts (optionally with signature), typically useful for
/// bundle contracts.
/// @dev Inherits the token safety requirements of Midnight (see Midnight.sol).
/// @dev Anyone authorized by the owner on Midnight can pull this contract's Blue positions through a take on Midnight
/// on behalf of OWNER.
/// @dev An account authorized on Blue to act on behalf of this contract can notably borrow on its behalf, which
/// is not the expected use-case, but it is not explicitly prevented because it does not affect onBuy.
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

    /// @dev Useful to handle rewards that the callback earned through its Blue positions.
    function skim(address token) external {
        uint256 balance = IERC20Extended(token).balanceOf(address(this));
        SafeTransferLib.safeTransfer(token, OWNER, balance);
        emit Skim(msg.sender, token, balance);
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
        ERC20Lib.safeApprove(market.loanToken, MIDNIGHT, buyerAssets);

        return CALLBACK_SUCCESS;
    }

    /// @dev Max buyerAssets amount that the callback can handle.
    /// @dev Takers receive the amount to take per offer from the routing layer. But the routing layer is
    /// asynchronous/offchain, and might not be up to date on the chain's latest state. To counter this, takers can
    /// query atomically this function to cap their take.
    /// @dev Ignores some static reasons why the bound might be smaller, such as wrong loan token, wrong owner... But it
    /// is easy for the routing layer to take that into account.
    /// @dev Reverts if data is not well formed.
    /// @dev Under-estimates the real bound if the callback is the fee recipient of the blue market.
    function buyerAssetsBound(bytes32, Market memory, address, bytes memory data) external view returns (uint256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));

        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
            IMorpho(BLUE).expectedMarketBalances(marketParams);
        uint256 supplyAssets = IMorpho(BLUE)
            .position(marketParams.id(), address(this))
            .supplyShares
            .toAssetsDown(totalSupplyAssets, totalSupplyShares);
        uint256 liquidity = totalSupplyAssets - totalBorrowAssets;
        uint256 blueBalance = IERC20Extended(marketParams.loanToken).balanceOf(BLUE);

        return UtilsLib.min(UtilsLib.min(supplyAssets, liquidity), blueBalance);
    }
}
