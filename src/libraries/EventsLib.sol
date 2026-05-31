// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market} from "../interfaces/IMidnight.sol";

/// @dev id_ is used to avoid naming conflicts in indexers.
library EventsLib {
    // forgefmt: disable-start
    event Constructor(address indexed roleSetter, uint256 initialChainId);
    event SetRoleSetter(address indexed roleSetter);
    event SetFeeSetter(address indexed feeSetter);
    event SetTickSpacingSetter(address indexed tickSpacingSetter);
    event SetMarketTickSpacing(bytes32 indexed id_, uint256 newTickSpacing);
    event SetMarketSettlementFee(bytes32 indexed id_, uint256 indexed index, uint256 newSettlementFee);
    event SetDefaultSettlementFee(address indexed loanToken, uint256 indexed index, uint256 newSettlementFee);
    event SetFeeClaimer(address indexed feeClaimer);
    event SetMarketContinuousFee(bytes32 indexed id_, uint256 newContinuousFee);
    event SetDefaultContinuousFee(address indexed loanToken, uint256 newContinuousFee);
    event UpdatePosition(bytes32 indexed id_, address indexed user, uint256 creditDecrease, uint256 pendingFeeDecrease, uint256 accruedFee);
    event MarketCreated(Market market, bytes32 indexed id_);
    event Take(address caller, bytes32 indexed id_, uint256 units, address indexed taker, address indexed maker, bool offerIsBuy, bytes32 group, uint256 buyerAssets, uint256 sellerAssets, uint256 consumed, uint256 buyerPendingFeeIncrease, uint256 sellerPendingFeeDecrease, uint256 buyerCreditIncrease, uint256 sellerCreditDecrease, address receiver, address payer);
    event Withdraw(address caller, bytes32 indexed id_, uint256 units, address indexed onBehalf, address indexed receiver, uint256 pendingFeeDecrease);
    event Repay(address indexed caller, bytes32 indexed id_, uint256 units, address indexed onBehalf, address payer);
    event SupplyCollateral(address caller, bytes32 indexed id_, address indexed collateral, uint256 assets, address indexed onBehalf);
    event WithdrawCollateral(address caller, bytes32 indexed id_, address indexed collateral, uint256 assets, address indexed onBehalf, address receiver);
    event Liquidate(address caller, bytes32 indexed id_, address indexed collateral, uint256 seizedAssets, uint256 repaidUnits, address indexed borrower, bool postMaturityMode, address receiver, address payer, uint256 badDebt, uint256 latestLossFactor, uint256 latestContinuousFeeCredit);
    event SetConsumed(address indexed caller, bytes32 indexed group, uint256 amount, address indexed onBehalf);
    event FlashLoan(address indexed caller, address[] tokens, uint256[] assets, address indexed callback);
    event SetIsAuthorized(address indexed caller, address indexed authorized, bool newIsAuthorized, address indexed onBehalf);
    event ClaimContinuousFee(address indexed caller, bytes32 indexed id_, uint256 amount, address indexed receiver);
    event ClaimSettlementFee(address indexed caller, address indexed token, uint256 amount, address indexed receiver);
    // forgefmt: disable-end
}
