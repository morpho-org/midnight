// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {Obligation, Seizure} from "../interfaces/IMorphoV2.sol";

library EventsLib {
    event Multicall(address indexed caller, uint256 callsCount);

    event SetOwner(address indexed newOwner);

    event SetFeeSetter(address indexed newFeeSetter);

    event SetTradingFee(bytes32 indexed id, uint128 tradingFee, uint128 interestCutLimit);

    event SetTradingFeeRecipient(address indexed recipient);

    event Take(
        bytes32 indexed id,
        Obligation obligation,
        address indexed buyer,
        address indexed seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares
    );

    event Withdraw(bytes32 indexed id, address indexed onBehalf, uint256 obligationUnits, uint256 shares);

    event Repay(bytes32 indexed id, address indexed onBehalf, uint256 obligationUnits);

    event SupplyCollateral(
        bytes32 indexed id, Obligation obligation, address indexed onBehalf, address indexed collateral, uint256 assets
    );

    event WithdrawCollateral(
        bytes32 indexed id, address indexed onBehalf, address indexed collateral, uint256 assets
    );

    event Liquidate(
        bytes32 indexed id,
        address indexed borrower,
        address indexed liquidator,
        uint256 totalRepaid,
        uint256 badDebt,
        Seizure[] seizures
    );

    event Consume(address indexed user, bytes32 indexed group, uint256 amount);

    event ShuffleNonce(address indexed user, bytes32 oldNonce, bytes32 newNonce);

    event FlashLoan(address indexed borrower, address indexed token, uint256 amount, address callback);
}