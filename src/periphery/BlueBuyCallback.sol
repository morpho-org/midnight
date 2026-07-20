// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, MarketParams} from "morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {IBlueBuyCallback} from "./interfaces/IBlueBuyCallback.sol";

interface IERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @dev Anyone authorized by the owner on Midnight can pull from the Blue position held by this callback contract by
/// making the owner buy dummy credit on Midnight.
/// @dev Reverts if the owner position on the requested market is too small or if the liquidity on that market is too
/// small.
contract BlueBuyCallback is IBlueBuyCallback {
    address public immutable OWNER;
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    constructor(address _owner, address _midnight, address _blue) {
        OWNER = _owner;
        MIDNIGHT = _midnight;
        BLUE = _blue;

        IMorpho(BLUE).setAuthorization(OWNER, true);
    }

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

        MarketParams memory blueMarketParams = abi.decode(data, (MarketParams));
        require(blueMarketParams.loanToken == market.loanToken, InconsistentLoanToken());

        if (buyerAssets > 0) IMorpho(BLUE).withdraw(blueMarketParams, buyerAssets, 0, address(this), address(this));
        forceApproveMax(market.loanToken, MIDNIGHT);

        return CALLBACK_SUCCESS;
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
