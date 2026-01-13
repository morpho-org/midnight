// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Seizure} from "../interfaces/IMorphoV2.sol";

library EventsLib {
    event Constructor(address indexed owner);

    event SetOwner(address indexed owner);
    event SetFeeSetter(address indexed feeSetter);
    event SetTradingFee(bytes32 indexed obligationId, uint256 tradingFee, uint256 interestCutLimit);
    event SetTradingFeeRecipient(address indexed recipient);

    event Take(
        address indexed caller,
        bytes32 indexed obligationId,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address indexed taker,
        bool buyerIsLender,
        bool sellerIsBorrower
    );
    event Withdraw(
        address indexed caller,
        bytes32 indexed obligationId,
        uint256 obligationUnits,
        uint256 shares,
        address indexed onBehalf
    );
    event Repay(
        address indexed caller, bytes32 indexed obligationId, uint256 obligationUnits, address indexed onBehalf
    );
    event SupplyCollateral(
        address caller,
        bytes32 indexed obligationId,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf
    );

    event WithdrawCollateral(
        address caller,
        bytes32 indexed obligationId,
        address indexed collateral,
        uint256 assets,
        address indexed onBehalf
    );

    event Liquidate(
        address indexed caller,
        bytes32 indexed obligationId,
        Seizure[] seizures,
        address indexed borrower,
        uint256 totalRepaid,
        uint256 badDebt
    );

    event Consume(address indexed user, bytes32 indexed group, uint256 amount);
    event ShuffleSession(address indexed user, bytes32 session);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);
}
