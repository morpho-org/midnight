// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMidnight.sol";

/// @dev id_ is used to avoid naming conflicts in indexers.
library EventsLib {
    event Constructor(address indexed owner);

    event SetOwner(address indexed owner);
    event SetFeeSetter(address indexed feeSetter);
    event SetObligationTradingFee(bytes32 indexed id_, uint256 indexed index, uint256 newTradingFee);
    event SetDefaultTradingFee(address indexed loanToken, uint256 indexed index, uint256 newTradingFee);
    event SetFeeRecipient(address indexed feeRecipient);
    event SetObligationContinuousFee(bytes32 indexed id_, uint256 newContinuousFee);
    event SetDefaultContinuousFee(address indexed loanToken, uint256 newContinuousFee);
    event UpdatePosition(
        bytes32 indexed id_, address indexed user, uint256 newCredit, uint256 newPendingFee, uint256 accruedFee
    );
    event ObligationCreated(bytes32 indexed id_, Obligation obligation);
    event Take(
        address caller,
        bytes32 indexed id_,
        address indexed maker,
        address indexed taker,
        bool offerIsBuy,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        address sellerReceiver,
        bytes32 group,
        uint256 consumed,
        uint256 totalUnits,
        uint256 buyerPendingFee,
        uint256 sellerPendingFee,
        uint256 buyerCreditIncrease,
        uint256 sellerCreditDecrease
    );
    event Withdraw(
        address caller,
        bytes32 indexed id_,
        uint256 units,
        address indexed onBehalf,
        address indexed receiver,
        uint256 pendingFee
    );
    event Repay(address indexed caller, bytes32 indexed id_, uint256 units, address indexed onBehalf);
    event SupplyCollateral(
        address caller, bytes32 indexed id_, address indexed collateral, uint256 assets, address indexed onBehalf
    );

    event WithdrawCollateral(
        address caller,
        bytes32 indexed id_,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf,
        address receiver
    );

    event Liquidate(
        address indexed caller,
        bytes32 indexed id_,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address indexed borrower,
        uint256 badDebt,
        uint256 latestLossIndex
    );

    event SetConsumed(address indexed caller, address indexed onBehalf, bytes32 indexed group, uint256 amount);
    event ShuffleSession(address indexed caller, address indexed onBehalf, bytes32 session);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);

    event SetIsAuthorized(
        address indexed caller, address indexed onBehalf, address indexed authorized, bool newIsAuthorized
    );
}
