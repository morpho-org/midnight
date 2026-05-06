// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Obligation {
    address loanToken;
    CollateralParams[] collateralParams;
    uint256 maturity;
    uint256 rcfThreshold;
    address enterGate;
    address liquidatorGate;
}

struct CollateralParams {
    address token;
    uint256 lltv;
    uint256 maxLif;
    address oracle;
}

struct Offer {
    Obligation obligation;
    bool buy;
    address maker;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
    address ratifier;
    bool reduceOnly;
    uint256 maxUnits;
    uint256 maxSellerAssets;
    uint256 maxBuyerAssets;
}

struct ObligationState {
    uint128 totalUnits;
    uint128 lossFactor;
    uint128 withdrawable;
    uint128 continuousFeeCredit;
    uint16 tradingFee0;
    uint16 tradingFee1;
    uint16 tradingFee2;
    uint16 tradingFee3;
    uint16 tradingFee4;
    uint16 tradingFee5;
    uint16 tradingFee6;
    uint32 continuousFee;
    bool created;
}

struct Position {
    uint128 credit;
    uint128 pendingFee;
    uint128 lossFactor;
    uint128 lastAccrual;
    uint128 debt;
    uint128 collateralBitmap;
    uint128[128] collateral;
}

interface IMidnight {
    /// ERRORS ///
    error AlreadyConsumed();
    error BuyerGatedFromIncreasingCredit();
    error CollateralParamsNotSorted();
    error ConsumedBuyerAssets();
    error ConsumedSellerAssets();
    error ConsumedUnits();
    error ContinuousFeeTooHigh();
    error FeeNotMultipleOfFeeStep();
    error InconsistentInput();
    error WrongBuyCallbackReturnValue();
    error WrongSellCallbackReturnValue();
    error WrongRepayCallbackReturnValue();
    error WrongLiquidateCallbackReturnValue();
    error WrongFlashLoanCallbackReturnValue();
    error InvalidFeeIndex();
    error InvalidMaxLif();
    error InvalidProof();
    error InvalidSession();
    error LiquidatorGatedFromLiquidating();
    error LltvNotAllowed();
    error MakerCreditOrDebtIncreased();
    error MaturityTooFar();
    error MultipleNonZero();
    error NoCollateralParams();
    error NotLiquidatable();
    error ObligationLossFactorMaxedOut();
    error ObligationNotCreated();
    error OfferExpired();
    error OfferNotStarted();
    error OnlyFeeClaimer();
    error OnlyFeeSetter();
    error OnlyRoleSetter();
    error RatifierFail();
    error RatifierUnauthorized();
    error RecoveryCloseFactorConditionsViolated();
    error SelfTake();
    error SellerGatedFromIncreasingDebt();
    error SellerIsLiquidatable();
    error TakerUnauthorized();
    error TooManyActivatedCollaterals();
    error TooManyCollateralParams();
    error TradingFeeTooHigh();
    error Unauthorized();
    error UnhealthyBorrower();

    // forgefmt: disable-start
    /// IMMUTABLES ///
    function INITIAL_CHAIN_ID() external view returns (uint256);

    /// STORAGE GETTERS ///
    function position(bytes32 id, address user) external view returns (uint128 credit, uint128 pendingFee, uint128 lossFactor, uint128 lastAccrual, uint128 debt, uint128 collateralBitmap);
    function obligationState(bytes32 id) external view returns (uint128 totalUnits, uint128 lossFactor, uint128 withdrawable, uint128 continuousFeeCredit, uint16 tradingFee0, uint16 tradingFee1, uint16 tradingFee2, uint16 tradingFee3, uint16 tradingFee4, uint16 tradingFee5, uint16 tradingFee6, uint32 continuousFee, bool created);
    function consumed(address user, bytes32 group) external view returns (uint256);
    function session(address user) external view returns (bytes32);
    function isAuthorized(address authorizer, address authorized) external view returns (bool);
    function defaultTradingFees(address loanToken, uint256 index) external view returns (uint16);
    function defaultContinuousFee(address loanToken) external view returns (uint32);
    function claimableTradingFee(address token) external view returns (uint256);
    function roleSetter() external view returns (address);
    function feeSetter() external view returns (address);
    function feeClaimer() external view returns (address);

    /// MULTICALL ///
    function multicall(bytes[] memory calls) external;

    /// ADMIN FUNCTIONS ///
    function setRoleSetter(address newRoleSetter) external;
    function setFeeSetter(address newFeeSetter) external;
    function setFeeClaimer(address newFeeClaimer) external;
    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external;
    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external;
    function setObligationContinuousFee(bytes32 id, uint256 newContinuousFee) external;
    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external;
    function claimTradingFee(address token, uint256 amount, address receiver) external;
    function claimContinuousFee(Obligation memory obligation, uint256 amount, address receiver) external;

    /// ENTRY-POINTS ///
    function take(uint256 units, address taker, address takerCallback, bytes memory takerCallbackData, address receiverIfTakerIsSeller, Offer memory offer, bytes memory ratifierData, bytes32 root, bytes32[] memory proof) external returns (uint256, uint256, uint256);
    function withdraw(Obligation memory obligation, uint256 units, address onBehalf, address receiver) external;
    function repay(Obligation memory obligation, uint256 units, address onBehalf, address callback, bytes memory data) external;
    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf) external;
    function withdrawCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) external;
    function liquidate(Obligation memory obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes memory data) external returns (uint256, uint256);
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external;
    function shuffleSession(address onBehalf) external;
    function setIsAuthorized(address onBehalf, address authorized, bool newIsAuthorized) external;
    function flashLoan(address[] memory tokens, uint256[] memory assets, address callback, bytes memory data) external;
    function touchObligation(Obligation memory obligation) external returns (bytes32);

    /// SLASHING AND CONTINUOUS FEE ACCRUAL ///
    function updatePositionView(Obligation memory obligation, bytes32 id, address user) external view returns (uint128, uint128, uint128);
    function updatePosition(Obligation memory obligation, address user) external returns (uint128, uint128, uint128);

    /// OTHER VIEW FUNCTIONS ///
    function userLossFactor(bytes32 id, address user) external view returns (uint128);
    function collateralBitmap(bytes32 id, address user) external view returns (uint128);
    function collateral(bytes32 id, address user, uint256 index) external view returns (uint128);
    function toId(Obligation memory obligation) external view returns (bytes32);
    function toObligation(bytes32 id) external view returns (Obligation memory);
    function creditOf(bytes32 id, address user) external view returns (uint256);
    function debtOf(bytes32 id, address user) external view returns (uint256);
    function totalUnits(bytes32 id) external view returns (uint256);
    function lossFactor(bytes32 id) external view returns (uint128);
    function obligationCreated(bytes32 id) external view returns (bool);
    function withdrawable(bytes32 id) external view returns (uint256);
    function tradingFees(bytes32 id) external view returns (uint16[7] memory);
    function continuousFee(bytes32 id) external view returns (uint32);
    function continuousFeeCredit(bytes32 id) external view returns (uint256);
    function pendingFee(bytes32 id, address user) external view returns (uint128);
    function lastAccrual(bytes32 id, address user) external view returns (uint128);
    function liquidationLocked(bytes32 id, address user) external view returns (bool);
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) external view returns (bool);
    function maxLif(uint256 lltv, uint256 cursor) external pure returns (uint256);
    function maxTradingFee(uint256 index) external pure returns (uint256);
    function tradingFee(bytes32 id, uint256 timeToMaturity) external view returns (uint256);
    // forgefmt: disable-end
}
