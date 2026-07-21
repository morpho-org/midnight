// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {CALLBACK_SUCCESS, WAD} from "../libraries/ConstantsLib.sol";
import {IBuyCallback, ISellCallback, IRepayCallback} from "../interfaces/ICallbacks.sol";
import {IMidnight, Market, CollateralParams} from "../interfaces/IMidnight.sol";

/// @dev Keeps a borrower's loan-token collateral leg equal to their debt, for markets where the loan token is also
/// activated as a collateral with lltv == WAD.
/// @dev The borrower must authorize this contract on Midnight (`setIsAuthorized`), and approve it to pull the loan
/// token, before using it as their take/repay callback.
/// @dev Should be set as the taker callback of a `take` that changes the user's debt (`onSell` for increases,
/// `onBuy` for a buyer netting down pre-existing debt), and as the callback of a `repay` (`onRepay`). It is not meant
/// to be used as a `liquidate` callback: the liquidator, not the borrower, chooses that callback.
contract DeltaNeutralCallback is IBuyCallback, ISellCallback, IRepayCallback {
    error CollateralNotFound();
    error Unauthorized();

    IMidnight public immutable MIDNIGHT;

    constructor(address midnight) {
        MIDNIGHT = IMidnight(midnight);
    }

    /// @dev A buyer nets down any pre-existing debt before accruing credit, so the buy side can also decrease debt
    /// (e.g. a borrower buying back their own units). Withdraws the matching collateral, funding the buyer's payment
    /// for the trade (`take` pulls it from this contract right after this callback returns).
    function onBuy(bytes32 id, Market memory market, uint256, uint256, uint256, address buyer, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == address(MIDNIGHT), Unauthorized());
        uint256 collateralIndex = deltaNeutralIndex(market);
        uint256 excess = MIDNIGHT.collateral(id, buyer, collateralIndex) - MIDNIGHT.debt(id, buyer);
        if (excess > 0) {
            MIDNIGHT.withdrawCollateral(market, collateralIndex, excess, buyer, address(this));
            SafeTransferLib.safeApprove(market.loanToken, address(MIDNIGHT), excess);
        }
        return CALLBACK_SUCCESS;
    }

    /// @dev Tops up the borrower's delta-neutral collateral by the debt increase, pulling the loan token from the
    /// borrower.
    function onSell(bytes32 id, Market memory market, uint256, uint256, uint256, address seller, address, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == address(MIDNIGHT), Unauthorized());
        uint256 collateralIndex = deltaNeutralIndex(market);
        uint256 shortfall = MIDNIGHT.debt(id, seller) - MIDNIGHT.collateral(id, seller, collateralIndex);
        if (shortfall > 0) {
            SafeTransferLib.safeTransferFrom(market.loanToken, seller, address(this), shortfall);
            SafeTransferLib.safeApprove(market.loanToken, address(MIDNIGHT), shortfall);
            MIDNIGHT.supplyCollateral(market, collateralIndex, shortfall, seller);
        }
        return CALLBACK_SUCCESS;
    }

    /// @dev Withdraws the repaid amount from the borrower's delta-neutral collateral and uses it to fund the repay.
    function onRepay(bytes32, Market memory market, uint256 units, address onBehalf, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == address(MIDNIGHT), Unauthorized());
        uint256 collateralIndex = deltaNeutralIndex(market);
        MIDNIGHT.withdrawCollateral(market, collateralIndex, units, onBehalf, address(this));
        SafeTransferLib.safeApprove(market.loanToken, address(MIDNIGHT), units);
        return CALLBACK_SUCCESS;
    }

    /// @dev Returns the index of the market's collateral matching the loan token with lltv == WAD.
    function deltaNeutralIndex(Market memory market) public pure returns (uint256) {
        for (uint256 i; i < market.collateralParams.length; i++) {
            CollateralParams memory params = market.collateralParams[i];
            if (params.token == market.loanToken && params.lltv == WAD) return i;
        }
        revert CollateralNotFound();
    }
}
