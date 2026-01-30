// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Seizure, Obligation} from "../interfaces/IMorphoV2.sol";

library EventsLib {
    event Constructor(address indexed owner);

    event SetOwner(address indexed owner);
    event SetFeeSetter(address indexed feeSetter);
    event SetObligationTradingFee(bytes32 indexed id, uint256 indexed index, uint256 newTradingFee);
    event SetDefaultTradingFee(address indexed loanToken, uint256 indexed index, uint256 newTradingFee);
    event SetTradingFeeRecipient(address indexed recipient);

    event ObligationCreated(bytes32 indexed id, Obligation obligation);
    event Take(
        address indexed caller,
        bytes32 indexed id,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address indexed taker,
        bool buyerIsLender,
        bool sellerIsBorrower
    );
    event Withdraw(
        address indexed caller, bytes32 indexed id, uint256 obligationUnits, uint256 shares, address indexed onBehalf
    );
    event Repay(address indexed caller, bytes32 indexed id, uint256 obligationUnits, address indexed onBehalf);
    event SupplyCollateral(
        address caller, bytes32 indexed id, address indexed collateral, uint256 assets, address indexed onBehalf
    );

    event WithdrawCollateral(
        address caller, bytes32 indexed id, address indexed collateral, uint256 assets, address indexed onBehalf
    );

    event Liquidate(
        address indexed caller,
        bytes32 indexed id,
        Seizure[] seizures,
        address indexed borrower,
        uint256 totalRepaid,
        uint256 badDebt
    );

    event Consume(address indexed user, bytes32 indexed group, uint256 amount);
    event ShuffleSession(address indexed user, bytes32 session);
    event FlashLoan(address indexed caller, address indexed token, uint256 assets);
}
