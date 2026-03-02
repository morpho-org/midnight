// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMidnight.sol";

/// @dev id_ is used to avoid naming conflicts in indexers.
library EventsLib {
    event Constructor(address indexed owner);

    event SetOwner(address indexed owner);
    event SetFeeSetter(address indexed feeSetter);
    event SetObligationTradingFee(bytes20 indexed id_, uint256 indexed index, uint256 newTradingFee);
    event SetDefaultTradingFee(address indexed loanToken, uint256 indexed index, uint256 newTradingFee);
    event SetTradingFeeRecipient(address indexed feeRecipient);

    event ObligationCreated(bytes20 indexed id_, Obligation obligation);
    event Take(
        address caller,
        bytes20 indexed id_,
        address indexed maker,
        address indexed taker,
        bool offerIsBuy,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bool buyerIsLender,
        bool sellerIsBorrower,
        address sellerReceiver,
        bytes32 group,
        uint256 consumed
    );
    event Withdraw(
        address caller,
        bytes20 indexed id_,
        uint256 obligationUnits,
        uint256 shares,
        address indexed onBehalf,
        address indexed receiver
    );
    event Repay(address indexed caller, bytes20 indexed id_, uint256 obligationUnits, address indexed onBehalf);
    event SupplyCollateral(
        address caller, bytes20 indexed id_, address indexed collateral, uint256 assets, address indexed onBehalf
    );

    event WithdrawCollateral(
        address caller,
        bytes20 indexed id_,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf,
        address receiver
    );

    event Liquidate(
        address indexed caller,
        bytes20 indexed id_,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address indexed borrower,
        uint256 badDebt
    );

    event Consume(address indexed user, bytes32 indexed group, uint256 amount);
    event ShuffleSession(address indexed user, bytes32 session);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);

    event SetIsAuthorized(address indexed authorizer, address indexed authorized, bool newIsAuthorized);
}
