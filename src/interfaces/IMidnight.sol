// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Market {
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
    Market market;
    bool buy;
    address maker;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
    address ratifier;
    bool reduceOnly;
    uint256 maxUnits;
    uint256 maxAssets; // buyerAssets if offer.buy else sellerAssets
}

/// @dev Settlement fee cbp values and the continuous fee are 0 until the market is created, then set to the default
/// values.
struct MarketState {
    uint128 totalUnits;
    uint128 lossFactor;
    uint128 withdrawable;
    uint128 continuousFeeCredit;
    uint16 settlementFeeCbp0;
    uint16 settlementFeeCbp1;
    uint16 settlementFeeCbp2;
    uint16 settlementFeeCbp3;
    uint16 settlementFeeCbp4;
    uint16 settlementFeeCbp5;
    uint16 settlementFeeCbp6;
    uint32 continuousFee;
    uint8 tickSpacing;
}

struct Position {
    uint128 credit;
    uint128 pendingFee;
    uint128 lastLossFactor;
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
    error ConsumedAssets();
    error ConsumedUnits();
    error ContinuousFeeTooHigh();
    error FeeNotMultipleOfFeeCbp();
    error InconsistentInput();
    error WrongBuyCallbackReturnValue();
    error WrongSellCallbackReturnValue();
    error WrongRepayCallbackReturnValue();
    error WrongLiquidateCallbackReturnValue();
    error WrongFlashLoanCallbackReturnValue();
    error InvalidFeeIndex();
    error InvalidMaxLif();
    error InvalidTickSpacing();
    error LiquidatorGatedFromLiquidating();
    error LltvNotAllowed();
    error MakerCreditOrDebtIncreased();
    error MaturityTooFar();
    error MultipleNonZero();
    error NoCollateralParams();
    error NotBorrower();
    error NotLiquidatable();
    error MarketLossFactorMaxedOut();
    error MarketNotCreated();
    error OfferExpired();
    error OfferNotStarted();
    error OnlyFeeClaimer();
    error OnlyFeeSetter();
    error OnlyRoleSetter();
    error OnlyTickSpacingSetter();
    error RatifierFail();
    error RatifierUnauthorized();
    error RecoveryCloseFactorConditionsViolated();
    error SelfTake();
    error SellerGatedFromIncreasingDebt();
    error SellerIsLiquidatable();
    error TakerUnauthorized();
    error TickNotAccessible();
    error TooManyActivatedCollaterals();
    error TooManyCollateralParams();
    error SettlementFeeTooHigh();
    error Unauthorized();
    error UnhealthyBorrower();

    // forgefmt: disable-start
    /// IMMUTABLES ///
    function INITIAL_CHAIN_ID() external view returns (uint256);

    /// STORAGE GETTERS ///
    function position(bytes32 id, address user) external view returns (uint128 credit, uint128 pendingFee, uint128 lastLossFactor, uint128 lastAccrual, uint128 debt, uint128 collateralBitmap);
    function marketState(bytes32 id) external view returns (uint128 totalUnits, uint128 lossFactor, uint128 withdrawable, uint128 continuousFeeCredit, uint16 settlementFeeCbp0, uint16 settlementFeeCbp1, uint16 settlementFeeCbp2, uint16 settlementFeeCbp3, uint16 settlementFeeCbp4, uint16 settlementFeeCbp5, uint16 settlementFeeCbp6, uint32 continuousFee, uint8 tickSpacing);
    function consumed(address user, bytes32 group) external view returns (uint256);
    function isAuthorized(address authorizer, address authorized) external view returns (bool);
    function defaultSettlementFeeCbp(address loanToken, uint256 index) external view returns (uint16);
    function defaultContinuousFee(address loanToken) external view returns (uint32);
    function claimableSettlementFee(address token) external view returns (uint256);
    function roleSetter() external view returns (address);
    function feeSetter() external view returns (address);
    function feeClaimer() external view returns (address);
    function tickSpacingSetter() external view returns (address);

    /// MULTICALL ///
    function multicall(bytes[] memory calls) external;

    /// ADMIN FUNCTIONS ///
    function setRoleSetter(address newRoleSetter) external;
    function setFeeSetter(address newFeeSetter) external;
    function setFeeClaimer(address newFeeClaimer) external;
    function setTickSpacingSetter(address newTickSpacingSetter) external;
    function setMarketTickSpacing(bytes32 id, uint256 newTickSpacing) external;
    function setMarketSettlementFee(bytes32 id, uint256 index, uint256 newSettlementFee) external;
    function setDefaultSettlementFee(address loanToken, uint256 index, uint256 newSettlementFee) external;
    function setMarketContinuousFee(bytes32 id, uint256 newContinuousFee) external;
    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external;
    function claimSettlementFee(address token, uint256 amount, address receiver) external;
    function claimContinuousFee(Market memory market, uint256 amount, address receiver) external;

    /// ENTRY-POINTS ///
    function take(Offer memory offer, bytes memory ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes memory takerCallbackData) external returns (uint256, uint256);
    function withdraw(Market memory market, uint256 units, address onBehalf, address receiver) external;
    function repay(Market memory market, uint256 units, address onBehalf, address callback, bytes memory data) external;
    function supplyCollateral(Market memory market, uint256 collateralIndex, uint256 assets, address onBehalf) external;
    function withdrawCollateral(Market memory market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) external;
    function liquidate(Market memory market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes memory data) external returns (uint256, uint256);
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external;
    function setIsAuthorized(address authorized, bool newIsAuthorized, address onBehalf) external;
    function flashLoan(address[] memory tokens, uint256[] memory assets, address callback, bytes memory data) external;
    function touchMarket(Market memory market) external returns (bytes32);

    /// SLASHING AND CONTINUOUS FEE ACCRUAL ///
    function updatePositionView(Market memory market, bytes32 id, address user) external view returns (uint128, uint128, uint128);
    function updatePosition(Market memory market, address user) external returns (uint128, uint128, uint128);

    /// OTHER VIEW FUNCTIONS ///
    function lastLossFactor(bytes32 id, address user) external view returns (uint128);
    function collateralBitmap(bytes32 id, address user) external view returns (uint128);
    function collateral(bytes32 id, address user, uint256 index) external view returns (uint128);
    function toId(Market memory market) external view returns (bytes32);
    function toMarket(bytes32 id) external view returns (Market memory);
    function creditOf(bytes32 id, address user) external view returns (uint256);
    function debtOf(bytes32 id, address user) external view returns (uint256);
    function totalUnits(bytes32 id) external view returns (uint256);
    function lossFactor(bytes32 id) external view returns (uint128);
    function tickSpacing(bytes32 id) external view returns (uint8);
    function withdrawable(bytes32 id) external view returns (uint256);
    function settlementFeeCbps(bytes32 id) external view returns (uint16[7] memory);
    function continuousFee(bytes32 id) external view returns (uint32);
    function continuousFeeCredit(bytes32 id) external view returns (uint256);
    function pendingFee(bytes32 id, address user) external view returns (uint128);
    function lastAccrual(bytes32 id, address user) external view returns (uint128);
    function liquidationLocked(bytes32 id, address user) external view returns (bool);
    function isHealthy(Market memory market, bytes32 id, address borrower) external view returns (bool);
    function settlementFee(bytes32 id, uint256 timeToMaturity) external view returns (uint256);
    // forgefmt: disable-end
}
