// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "../../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "../../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {Market} from "../../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../../libraries/ConstantsLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {IBlueSwapBuyCallback} from "./interfaces/IBlueSwapBuyCallback.sol";
import {IERC20Extended} from "../blue-buy-callback/interfaces/IERC20Extended.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";
import {ERC20Lib} from "../libraries/ERC20Lib.sol";

/// @dev Funds Midnight buys by swapping a Blue supply position through a taker-selected ISwapper.
/// @dev data = abi.encode(abi.encode(MarketParams, limitPrice), abi.encode(swapper, swapData)).
/// @dev limitPrice is ORACLE_PRICE_SCALE-scaled raw Midnight loan token units per raw Blue loan token unit (including decimals).
/// @dev The positions on the Blue markets are acquired through supplies on behalf of this contract (permissionless).
/// @dev The OWNER can withdraw this position on Blue, for example if the offer expired.
/// @dev The OWNER can also authorize other accounts, typically useful for bundle contracts.
/// @dev Inherits the token safety requirements of Midnight (see Midnight.sol).
/// @dev Anyone authorized by the owner on Midnight can pull this contract's Blue positions through a take on Midnight on behalf of OWNER.
/// @dev An account authorized on Blue to act on behalf of this contract can notably borrow on its behalf, which is not the expected use-case, but it is not explicitly prevented because it does not affect onBuy.
contract BlueSwapBuyCallback is IBlueSwapBuyCallback {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;

    address public immutable OWNER;
    address public immutable MIDNIGHT;
    address public immutable BLUE;

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

    /// @dev Useful to handle rewards that the callback earned through its Blue positions.
    function skim(address token) external {
        uint256 balance = IERC20Extended(token).balanceOf(address(this));
        SafeTransferLib.safeTransfer(token, OWNER, balance);
        emit Skim(msg.sender, token, balance);
    }

    /// @dev Reverts if the owner position on the requested market is too small or if the liquidity on that market is too small.
    /// @dev For identical loan tokens, withdraws buyerAssets directly to this callback, ignoring limitPrice and takerData.
    function onBuy(
        bytes32 id,
        Market memory market,
        uint256 buyerAssets,
        uint256,
        uint256,
        address buyer,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        require(buyer == OWNER, NotOwnerBuyer());
        (bytes memory makerData, bytes memory takerData) = abi.decode(data, (bytes, bytes));
        (MarketParams memory marketParams, uint256 limitPrice) = abi.decode(makerData, (MarketParams, uint256));
        uint256 sourceAssets;
        address swapper;
        if (buyerAssets > 0 && marketParams.loanToken == market.loanToken) {
            sourceAssets = buyerAssets;
            IMorpho(BLUE).withdraw(marketParams, buyerAssets, 0, address(this), address(this));
        } else if (buyerAssets > 0) {
            sourceAssets = buyerAssets.mulDivDown(ORACLE_PRICE_SCALE, limitPrice);
            bytes memory swapData;
            (swapper, swapData) = abi.decode(takerData, (address, bytes));
            if (sourceAssets > 0) IMorpho(BLUE).withdraw(marketParams, sourceAssets, 0, address(this), swapper);
            require(
                ISwapper(swapper).onSwap(marketParams.loanToken, market.loanToken, sourceAssets, buyerAssets, swapData)
                    == CALLBACK_SUCCESS,
                InvalidSwapCallback()
            );
        }
        ERC20Lib.safeApprove(market.loanToken, MIDNIGHT, buyerAssets);
        emit OnBuy(msg.sender, id, buyerAssets, sourceAssets, swapper);
        return CALLBACK_SUCCESS;
    }

    /// @dev Available source assets in Blue loan-token units, without price conversion.
    /// @dev For same-token offers, max buyerAssets equals this bound. For cross-token offers, callers compute
    /// bound * limitPrice / ORACLE_PRICE_SCALE rounded down, using that offer's limitPrice from makerData.
    /// @dev Conversion is left to the caller because the price lives in each offer.
    /// @dev Takers receive the amount to take per offer from the routing layer. But the routing layer is asynchronous/offchain, and might not be up to date on the chain's latest state. To counter this, takers can query atomically this function to cap their take.
    /// @dev Ignores some static reasons why the bound might be smaller, such as wrong loan token, wrong owner... But it is easy for the routing layer to take that into account.
    /// @dev Reverts if data is not well formed.
    /// @dev Under-estimates the real bound if the callback is the fee recipient of the blue market.
    function buyerAssetsBound(bytes32, Market memory, address, bytes memory data) external view returns (uint256) {
        (bytes memory makerData,) = abi.decode(data, (bytes, bytes));
        (MarketParams memory marketParams,) = abi.decode(makerData, (MarketParams, uint256));

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
