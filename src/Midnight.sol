// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {IdLib} from "./libraries/IdLib.sol";
import {TickLib} from "./libraries/TickLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMidnight, Obligation, Offer, CollateralParams, ObligationState, Position} from "./interfaces/IMidnight.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {IRatifier} from "./interfaces/IRatifier.sol";
import {IEnterGate, ILiquidatorGate} from "./interfaces/IGate.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

struct SlashResult {
    uint128 postSlashCredit;
    uint128 postSlashPending;
}

struct LiquidateVars {
    uint256 maxDebt;
    uint256 liquidatedCollatPrice;
    uint256 originalDebt;
    uint256 badDebt;
    uint256 seizedAssets;
    uint256 repaidUnits;
}

struct TakeParams {
    uint256 units;
    address taker;
    address takerCallback;
    bytes takerCallbackData;
    address receiverIfTakerIsSeller;
    bytes ratifierData;
    bytes32 root;
    bytes32[] proof;
}

struct TakeVars {
    address buyer;
    address buyerCallback;
    bytes buyerCallbackData;
    address seller;
    address sellerCallback;
    bytes sellerCallbackData;
    address receiver;
    uint256 timeToMaturity;
    uint256 buyerAssets;
    uint256 sellerAssets;
    uint256 newConsumed;
    uint256 buyerCreditIncrease;
    uint256 sellerCreditDecrease;
    uint256 sellerDebtIncrease;
    uint128 buyerPendingFeeIncrease;
    uint128 sellerPendingFeeDecrease;
}

/// OBLIGATIONS
/// @dev The following constraints are enforced on obligation creation (in `touchObligation`):
/// - `collateralParams.length > 0`: at least one collateral is required.
/// - `collateralParams.length <= MAX_COLLATERALS` (128): at most 128 collateralParams per obligation.
/// - Collateral tokens must be non-zero and strictly sorted by address (ascending, no duplicates).
/// - Each collateral's `lltv` must be one of the allowed tiers (see `isLltvAllowed` in ConstantsLib).
/// - Each collateral's `maxLif` must equal `maxLif(lltv, LIQUIDATION_CURSOR_LOW)` or
///   `maxLif(lltv, LIQUIDATION_CURSOR_HIGH)`.
/// @dev Additionally, within a single obligation, a borrower can use at most MAX_COLLATERALS_PER_BORROWER (10)
/// collaterals simultaneously.
///
/// TRADING FEES
/// @dev A default trading fee (per loan token) is set on new obligations. Then, the fee setter can override it.
/// @dev The trading fee is computed using piecewise linear interpolation between breakpoints.
/// @dev Trading fee breakpoint indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d, 6=360d.
/// @dev For TTM > 360d, the trading fee is the fee at the 360d breakpoint.
/// @dev Post-maturity, the trading fee is the fee at the 0d breakpoint.
/// @dev Trading fees are stored divided by FEE_STEP (1e12) to fit in 16 bits.
/// @dev Max trading fee is defined per index: 50 bps for ttm=360 days, scaled linearly. For post maturity, 0.14 bps.
///
/// CONTINUOUS FEES
/// @dev A default continuous fee (per loan token) is set on new obligations. Then, the fee setter can override it.
/// @dev The fee is tracked per lender via `pendingFee` in each position. If the obligation's continuous fee changes,
/// the pending fee of existing lenders is not updated (=> their fee is fixed).
/// @dev Absent bad debt, the face value of a lender's position is `credit - pendingFee`.
///
/// SLASHING
/// @dev When some bad debt is realized, it is socialized among lenders in the obligation.
/// @dev At each lender's next interaction, their credit is slashed proportionally.
///
/// GROUPS
/// @dev Groups are useful to have a global offered amount shared across multiple offers ("OCO").
/// @dev To work as expected, all offers in the same group should have the same max values and loan token.
/// @dev Only one of `maxSellerAssets`, `maxBuyerAssets`, or `maxUnits` can be nonzero per offer.
///
/// SESSION
/// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
/// @dev Offers should have the current session to be valid.
///
/// AUTHORIZATIONS
/// @dev All functions that change the position, session, consumed and authorization are accessible to the user and to
/// any account that has been authorized.
/// @dev In particular, authorized accounts can authorize other accounts on behalf of the user.
/// @dev updatePosition and liquidate (for liquidatable users) also impact the position and are permissionless.
///
/// ROUNDINGS
/// @dev Because of roundings, trading and continuous fees might charge less than expected, which can become problematic
/// for chains where the gas is cheaper than 1 asset of the loan token.
/// @dev lossIndex is rounded up so lenders collectively lose a bit more on each bad debt realization.
/// @dev slash rounds the credit down, so lenders lose a bit at each interaction.
/// @dev If an obligation loses more than 99%+ of its value to bad debt over its lifetime, it won't function properly
/// afterwards (bad debt can no longer be realized).
///
/// GATES
/// @dev Gates are optional (address(0) = unrestricted).
/// @dev The entry gate can prevent entry actions (increasing credit or debt) in the obligation.
/// @dev In particular, it does not prevent the user from exiting the obligation even when the entry gate is reverting.
/// @dev The liquidator gate can prevent the user from liquidating borrowers in the obligation (and realizing bad debt).
///
/// TOKEN REQUIREMENTS
/// @dev List of assumptions on tokens that guarantee that Midnight behaves as expected:
/// - It should be ERC-20 compliant, except that it can omit return values on `transfer` and `transferFrom`.
/// - Midnight's balance of the token should only decrease on `transfer` and `transferFrom`.
/// - It should not re-enter Midnight on `transfer` nor `transferFrom`.
/// - Midnight must send/receive exactly the requested amount on transfers.
/// - It should not revert on `transfer` and `transferFrom` if balances and approvals are right.
/// - It should not revert on no-op transfers.
///
/// LIVENESS
/// @dev If an activated collateral oracle reverts on `price`, `liquidate`, `isHealthy`, `withdrawCollateral`  when the
/// borrower has debt, and `take` whenever the seller still has debt all revert.
/// @dev If an activated collateral oracle returns 0 on `price`, `isHealthy`, `withdrawCollateral` when the borrower has
/// debt, `take` whenever the seller still has debt, and `liquidate` with repaid input all revert.
/// @dev If `enterGate.canIncreaseCredit` reverts or returns false, `take` reverts if the buyer's credit increases.
/// @dev If `enterGate.canIncreaseDebt` reverts or returns false, `take` reverts if the seller's debt increases.
/// @dev If `liquidatorGate` reverts or returns false on `canLiquidate`, `liquidate` reverts.
/// @dev If a token pulled by Midnight reverts on `transferFrom` despite balances and approvals being right, `take`,
/// `repay`, `supplyCollateral`, `liquidate`, and `flashLoan` repayment revert when they need to pull that token.
/// @dev If a token sent by Midnight reverts on `transfer` despite balances being right, `withdraw`,
/// `withdrawCollateral`, fee claims, the collateral leg of `liquidate`, and `flashLoan` revert when they need to send
/// that token.
/// @dev If a callback reverts, or if a buy/sell callback returns something other than `CALLBACK_SUCCESS`,
/// callback-enabled `take`, `repay`, `liquidate`, and `flashLoan` revert.
///
/// ROLES
/// @dev The role setter can set the role setter, fee setter, and fee claimer.
/// @dev The fee setter can set the default and per-obligation trading fee and continuous fee.
/// @dev The fee claimer can claim the trading fee and continuous fee.
/// @dev When the claimer is set, the old claimer loses the unclaimed fees.
///
/// MISC
/// @dev The max amount of totalUnits, collateral, credit, and debt is type(uint128).max (~1e38).
/// @dev Zero checks are not systematically performed.
/// @dev No-ops are allowed.
/// @dev NatSpec comments are included only when they bring clarity.
///
contract Midnight is IMidnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => Position)) public position;
    mapping(bytes32 id => ObligationState) internal _obligationStates;
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;
    mapping(address user => bytes32) public session;
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;
    mapping(address loanToken => uint16[7]) public defaultTradingFees;
    mapping(address loanToken => uint32) public defaultContinuousFee;
    mapping(address token => uint256) public claimableTradingFee;
    address public roleSetter;
    address public feeSetter;
    address public feeClaimer;

    /// CONSTRUCTOR ///

    constructor() {
        roleSetter = msg.sender;
        emit EventsLib.Constructor(roleSetter);
    }

    /// STORAGE GETTER ///

    function obligationState(bytes32 id) external view returns (ObligationState memory) {
        return _obligationStates[id];
    }

    /// MULTICALL ///

    function multicall(bytes[] calldata calls) external {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(calls[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    /// ADMIN FUNCTIONS ///

    function setRoleSetter(address newRoleSetter) external {
        require(msg.sender == roleSetter, "only role setter");
        roleSetter = newRoleSetter;
        emit EventsLib.SetRoleSetter(newRoleSetter);
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == roleSetter, "only role setter");
        feeSetter = newFeeSetter;
        emit EventsLib.SetFeeSetter(newFeeSetter);
    }

    function setFeeClaimer(address newFeeClaimer) external {
        require(msg.sender == roleSetter, "only role setter");
        feeClaimer = newFeeClaimer;
        emit EventsLib.SetFeeClaimer(newFeeClaimer);
    }

    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        ObligationState storage _obligationState = _obligationStates[id];
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "trading fee too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        require(_obligationState.created, "obligation not created");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        uint16 toStore = uint16(newTradingFee / FEE_STEP);
        if (index == 0) _obligationState.fee0 = toStore;
        else if (index == 1) _obligationState.fee1 = toStore;
        else if (index == 2) _obligationState.fee2 = toStore;
        else if (index == 3) _obligationState.fee3 = toStore;
        else if (index == 4) _obligationState.fee4 = toStore;
        else if (index == 5) _obligationState.fee5 = toStore;
        else if (index == 6) _obligationState.fee6 = toStore;
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "trading fee too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        defaultTradingFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setObligationContinuousFee(bytes32 id, uint256 newContinuousFee) external {
        ObligationState storage _obligationState = _obligationStates[id];
        require(msg.sender == feeSetter, "only fee setter");
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, "continuous fee too high");
        require(_obligationState.created, "obligation not created");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        _obligationState.continuousFee = uint32(newContinuousFee);
        emit EventsLib.SetObligationContinuousFee(id, newContinuousFee);
    }

    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, "continuous fee too high");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        defaultContinuousFee[loanToken] = uint32(newContinuousFee);
        emit EventsLib.SetDefaultContinuousFee(loanToken, newContinuousFee);
    }

    function claimTradingFee(address token, uint256 amount, address receiver) external {
        require(msg.sender == feeClaimer, "only fee claimer");
        claimableTradingFee[token] -= amount;
        emit EventsLib.ClaimTradingFee(msg.sender, token, amount, receiver);
        SafeTransferLib.safeTransfer(token, receiver, amount);
    }

    function claimContinuousFee(Obligation memory obligation, uint256 amount, address receiver) external {
        bytes32 id = toId(obligation);
        ObligationState storage _obligationState = _obligationStates[id];
        require(msg.sender == feeClaimer, "only fee claimer");
        require(_obligationState.created, "obligation not created");

        _obligationState.continuousFeeCredit -= UtilsLib.toUint128(amount);
        _obligationState.totalUnits -= UtilsLib.toUint128(amount);
        _obligationState.withdrawable -= UtilsLib.toUint128(amount);

        emit EventsLib.ClaimContinuousFee(msg.sender, id, amount, receiver);

        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, amount);
    }

    /// ENTRY-POINTS ///

    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev The taker might not get the price they expected if the trading fee was just changed.
    /// @dev All sellerAssets are reachable with the units input, and all buyerAssets are reachable only if
    /// buyerPrice <= WAD.
    /// @dev The seller cannot be liquidated during the callbacks of a take.
    /// @dev Returns buyerAssets, sellerAssets, units.
    function take(
        uint256 units,
        address taker,
        address takerCallback,
        bytes memory takerCallbackData,
        address receiverIfTakerIsSeller,
        Offer memory offer,
        bytes memory ratifierData,
        bytes32 root,
        bytes32[] memory proof
    ) external returns (uint256, uint256, uint256) {
        return _take(
            TakeParams({
                units: units,
                taker: taker,
                takerCallback: takerCallback,
                takerCallbackData: takerCallbackData,
                receiverIfTakerIsSeller: receiverIfTakerIsSeller,
                ratifierData: ratifierData,
                root: root,
                proof: proof
            }),
            offer
        );
    }

    function _take(TakeParams memory params, Offer memory offer) internal returns (uint256, uint256, uint256) {
        bytes32 id = touchObligation(offer.obligation);
        require(
            UtilsLib.atMostOneNonZero(offer.maxSellerAssets, offer.maxBuyerAssets, offer.maxUnits), "multiple max"
        );
        require(params.taker == msg.sender || isAuthorized[params.taker][msg.sender], "taker unauthorized");
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(offer.maker != params.taker, "cannot self take");
        require(
            UtilsLib.isLeaf(params.root, keccak256(abi.encode(offer)), params.proof), "invalid proof"
        );
        require(offer.session == session[offer.maker], "invalid session");
        require(isAuthorized[offer.maker][offer.ratifier], "ratifier unauthorized");
        require(
            IRatifier(offer.ratifier).onRatify(offer, params.root, params.ratifierData) == CALLBACK_SUCCESS,
            "not ratified"
        );

        TakeVars memory vars;

        if (offer.buy) {
            vars.buyer = offer.maker;
            vars.buyerCallback = offer.callback;
            vars.buyerCallbackData = offer.callbackData;
            vars.seller = params.taker;
            vars.sellerCallback = params.takerCallback;
            vars.sellerCallbackData = params.takerCallbackData;
            vars.receiver = params.receiverIfTakerIsSeller;
        } else {
            vars.buyer = params.taker;
            vars.buyerCallback = params.takerCallback;
            vars.buyerCallbackData = params.takerCallbackData;
            vars.seller = offer.maker;
            vars.sellerCallback = offer.callback;
            vars.sellerCallbackData = offer.callbackData;
            vars.receiver = offer.receiverIfMakerIsSeller;
        }

        _computeTakeAmounts(offer, id, params.units, vars);

        if (offer.maxSellerAssets > 0) {
            vars.newConsumed = consumed[offer.maker][offer.group] += vars.sellerAssets;
            require(vars.newConsumed <= offer.maxSellerAssets, "consumed seller assets");
        } else if (offer.maxBuyerAssets > 0) {
            vars.newConsumed = consumed[offer.maker][offer.group] += vars.buyerAssets;
            require(vars.newConsumed <= offer.maxBuyerAssets, "consumed buyer assets");
        } else {
            vars.newConsumed = consumed[offer.maker][offer.group] += params.units;
            require(vars.newConsumed <= offer.maxUnits, "consumed units");
        }

        {
            ObligationState storage _obligationState = _obligationStates[id];
            Position storage buyerPos = position[id][vars.buyer];
            Position storage sellerPos = position[id][vars.seller];

            if (hasCredit(id, vars.buyer) || params.units > buyerPos.debt) {
                _updatePosition(offer.obligation, id, vars.buyer);
            }
            if (hasCredit(id, vars.seller)) _updatePosition(offer.obligation, id, vars.seller);

            vars.buyerCreditIncrease = UtilsLib.zeroFloorSub(params.units, buyerPos.debt);
            vars.sellerCreditDecrease = UtilsLib.min(params.units, sellerPos.credit);
            vars.sellerDebtIncrease = params.units - vars.sellerCreditDecrease;
            vars.buyerPendingFeeIncrease = UtilsLib.toUint128(
                vars.buyerCreditIncrease.mulDivDown(_obligationState.continuousFee * vars.timeToMaturity, WAD)
            );
            vars.sellerPendingFeeDecrease = sellerPos.credit > 0
                ? UtilsLib.toUint128(sellerPos.pendingFee.mulDivUp(vars.sellerCreditDecrease, sellerPos.credit))
                : 0;

            buyerPos.debt -= UtilsLib.toUint128(params.units - vars.buyerCreditIncrease);
            buyerPos.pendingFee += vars.buyerPendingFeeIncrease;
            buyerPos.credit += UtilsLib.toUint128(vars.buyerCreditIncrease);

            sellerPos.pendingFee -= vars.sellerPendingFeeDecrease;
            sellerPos.credit -= UtilsLib.toUint128(vars.sellerCreditDecrease);
            sellerPos.debt += UtilsLib.toUint128(vars.sellerDebtIncrease);

            _obligationState.totalUnits =
                UtilsLib.toUint128(_obligationState.totalUnits + vars.buyerCreditIncrease - vars.sellerCreditDecrease);

            require(buyerPos.pendingFee <= buyerPos.credit, "buyer pendingFee exceeds credit");
        }

        if (offer.reduceOnly) {
            require(
                offer.buy ? vars.buyerCreditIncrease == 0 : vars.sellerDebtIncrease == 0,
                "maker credit or debt increased"
            );
        }

        require(
            offer.obligation.enterGate == address(0) || vars.buyerCreditIncrease == 0
                || IEnterGate(offer.obligation.enterGate).canIncreaseCredit(vars.buyer),
            "buyer gated from increasing credit"
        );
        require(
            offer.obligation.enterGate == address(0) || vars.sellerDebtIncrease == 0
                || IEnterGate(offer.obligation.enterGate).canIncreaseDebt(vars.seller),
            "seller gated from increasing debt"
        );

        emit EventsLib.Take(
            msg.sender,
            id,
            offer.maker,
            params.taker,
            offer.buy,
            vars.buyerAssets,
            vars.sellerAssets,
            params.units,
            vars.receiver,
            offer.group,
            vars.newConsumed,
            vars.buyerPendingFeeIncrease,
            vars.sellerPendingFeeDecrease,
            vars.buyerCreditIncrease,
            vars.sellerCreditDecrease
        );

        bool wasLocked = UtilsLib.tExchange(LIQUIDATION_LOCK_SLOT, id, vars.seller, true);
        if (vars.buyerCallback != address(0)) {
            require(
                ICallbacks(vars.buyerCallback).onBuy(
                    id, offer.obligation, vars.buyer, vars.buyerAssets, params.units, vars.buyerCallbackData
                ) == CALLBACK_SUCCESS,
                "invalid callback"
            );
        }

        {
            address payer =
                vars.buyerCallback != address(0) ? vars.buyerCallback : (offer.buy ? vars.buyer : msg.sender);
            SafeTransferLib.safeTransferFrom(
                offer.obligation.loanToken, payer, address(this), vars.buyerAssets - vars.sellerAssets
            );
            claimableTradingFee[offer.obligation.loanToken] += vars.buyerAssets - vars.sellerAssets;
            SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, payer, vars.receiver, vars.sellerAssets);
        }

        if (vars.sellerCallback != address(0)) {
            require(
                ICallbacks(vars.sellerCallback).onSell(
                    id, offer.obligation, vars.seller, vars.sellerAssets, params.units, vars.sellerCallbackData
                ) == CALLBACK_SUCCESS,
                "invalid callback"
            );
        }
        if (!wasLocked) UtilsLib.tExchange(LIQUIDATION_LOCK_SLOT, id, vars.seller, false);
        require(!isLiquidatable(offer.obligation, id, vars.seller), "seller is liquidatable");

        return (vars.buyerAssets, vars.sellerAssets, params.units);
    }

    function _computeTakeAmounts(Offer memory offer, bytes32 id, uint256 units, TakeVars memory vars) internal view {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        vars.timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        uint256 _tradingFee = tradingFee(id, vars.timeToMaturity);
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        vars.buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD);
        vars.sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD);
    }

    /// @dev Will revert if there are no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 units, address onBehalf, address receiver) external {
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = _obligationStates[id];
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        _updatePosition(obligation, id, onBehalf);

        Position storage _position = position[id][onBehalf];
        uint128 pendingFeeDecrease;
        if (_position.credit > 0) {
            pendingFeeDecrease = UtilsLib.toUint128(_position.pendingFee.mulDivUp(units, _position.credit));
            _position.pendingFee -= pendingFeeDecrease;
        }
        _position.credit -= UtilsLib.toUint128(units);
        _obligationState.withdrawable -= UtilsLib.toUint128(units);
        _obligationState.totalUnits -= UtilsLib.toUint128(units);

        emit EventsLib.Withdraw(msg.sender, id, units, onBehalf, receiver, pendingFeeDecrease);

        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, units);
    }

    function repay(Obligation memory obligation, uint256 units, address onBehalf, bytes calldata data) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);

        position[id][onBehalf].debt -= UtilsLib.toUint128(units);
        _obligationStates[id].withdrawable += UtilsLib.toUint128(units);

        emit EventsLib.Repay(msg.sender, id, units, onBehalf);

        if (data.length > 0) {
            ICallbacks(msg.sender).onRepay(id, obligation, units, onBehalf, data);
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), units);
    }

    /// @dev This function checks authorization to prevent activated collateral poisoning.
    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collateralParams[collateralIndex].token;
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");

        Position storage _position = position[id][onBehalf];
        uint256 oldCollateral = _position.collateral[collateralIndex];
        _position.collateral[collateralIndex] = UtilsLib.toUint128(oldCollateral + assets);

        if (oldCollateral == 0 && assets > 0) {
            uint128 newBitmap = _position.activatedCollaterals.setBit(collateralIndex);
            _position.activatedCollaterals = newBitmap;
            require(UtilsLib.countBits(newBitmap) <= MAX_COLLATERALS_PER_BORROWER, "too many activated collaterals");
        }

        emit EventsLib.SupplyCollateral(msg.sender, id, collateralToken, assets, onBehalf);

        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, address(this), assets);
    }

    /// @dev This function does not call any oracle if all the collateral is withdrawn and the borrower has no debt.
    function withdrawCollateral(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collateralParams[collateralIndex].token;
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");

        Position storage _position = position[id][onBehalf];
        uint256 newCollateral = _position.collateral[collateralIndex] - assets;
        _position.collateral[collateralIndex] = UtilsLib.toUint128(newCollateral);

        if (newCollateral == 0 && assets > 0) {
            _position.activatedCollaterals = _position.activatedCollaterals.clearBit(collateralIndex);
        }

        require(isHealthy(obligation, id, onBehalf), "unhealthy borrower");

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateralToken, assets, onBehalf, receiver);

        SafeTransferLib.safeTransfer(collateralToken, receiver, assets);
    }

    /// @dev At least one of `seizedAssets` or `repaidUnits` should be equal to zero.
    /// @dev Accounts with nonzero debt are liquidatable if they are unhealthy or if the maturity has passed.
    /// @dev Before maturity, the liquidation cannot put the borrower back into health (recovery close factor), unless
    /// the liquidation could leave a collateral with a value that would not be enough to repay rcfThreshold units.
    /// @dev Recovery close factor means that debtOf - repaidUnits >= maxDebt - repaidUnits*LIF*LLTV, which is
    /// equivalent to repaidUnits <= (debtOf-maxDebt) / (1 - LIF*LLTV).
    /// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to maxLif(lltv) at maturity +
    /// TIME_TO_MAX_LIF.
    /// @dev Returns the seized assets and the repaid units.
    function liquidate(
        Obligation calldata obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes calldata data
    ) external returns (uint256, uint256) {
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = _obligationStates[id];
        Position storage _position = position[id][borrower];
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), "inconsistent input");
        require(
            obligation.liquidatorGate == address(0)
                || ILiquidatorGate(obligation.liquidatorGate).canLiquidate(msg.sender),
            "liquidator gated from liquidating"
        );

        LiquidateVars memory vars;
        vars.originalDebt = _position.debt;
        vars.badDebt = vars.originalDebt;
        vars.seizedAssets = seizedAssets;
        vars.repaidUnits = repaidUnits;
        _computeLiquidationLoop(obligation, collateralIndex, _position, vars);

        require(
            vars.originalDebt > 0 && !liquidationLocked(id, borrower)
                && (block.timestamp > obligation.maturity || vars.originalDebt > vars.maxDebt),
            "not liquidatable"
        );

        if (vars.badDebt > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(vars.badDebt);
            uint256 oldTotalUnits = _obligationState.totalUnits;
            uint256 oldLossIndex = _obligationState.lossIndex;
            _obligationState.lossIndex = UtilsLib.toUint128(
                type(uint128).max
                    - (type(uint128).max - oldLossIndex).mulDivDown(oldTotalUnits - vars.badDebt, oldTotalUnits)
            );
            _obligationState.totalUnits -= UtilsLib.toUint128(vars.badDebt);
            _obligationState.continuousFeeCredit = oldLossIndex < type(uint128).max
                ? UtilsLib.toUint128(
                    _obligationState.continuousFeeCredit
                        .mulDivDown(type(uint128).max - _obligationState.lossIndex, type(uint128).max - oldLossIndex)
                )
                : 0;
        }

        if (vars.repaidUnits > 0 || vars.seizedAssets > 0) {
            _applyLiquidationRepayment(obligation, collateralIndex, _obligationState, _position, vars);
        }

        emit EventsLib.Liquidate(
            msg.sender,
            id,
            obligation.collateralParams[collateralIndex].token,
            vars.seizedAssets,
            vars.repaidUnits,
            borrower,
            vars.badDebt,
            _obligationState.lossIndex
        );

        SafeTransferLib.safeTransfer(
            obligation.collateralParams[collateralIndex].token, msg.sender, vars.seizedAssets
        );

        if (data.length > 0) {
            ICallbacks(msg.sender).onLiquidate(
                id, obligation, collateralIndex, vars.seizedAssets, vars.repaidUnits, borrower, data
            );
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), vars.repaidUnits);

        return (vars.seizedAssets, vars.repaidUnits);
    }

    function _computeLiquidationLoop(
        Obligation calldata obligation,
        uint256 collateralIndex,
        Position storage _position,
        LiquidateVars memory vars
    ) internal view {
        uint128 bitmap = _position.activatedCollaterals;
        while (bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            CollateralParams memory _collateralParam = obligation.collateralParams[i];
            uint256 price = IOracle(_collateralParam.oracle).price();
            if (i == collateralIndex) vars.liquidatedCollatPrice = price;
            uint256 _collateral = _position.collateral[i];
            vars.maxDebt += _collateral.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateralParam.lltv, WAD);
            vars.badDebt = vars.badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
            );
            bitmap = bitmap.clearBit(i);
        }
    }

    function _applyLiquidationRepayment(
        Obligation calldata obligation,
        uint256 collateralIndex,
        ObligationState storage _obligationState,
        Position storage _position,
        LiquidateVars memory vars
    ) internal {
        uint256 lif;
        {
            uint256 _maxLif = obligation.collateralParams[collateralIndex].maxLif;
            lif = vars.originalDebt > vars.maxDebt
                ? _maxLif
                : UtilsLib.min(
                    _maxLif, WAD + (_maxLif - WAD) * (block.timestamp - obligation.maturity) / TIME_TO_MAX_LIF
                );
        }

        if (vars.seizedAssets > 0) {
            vars.repaidUnits =
                vars.seizedAssets.mulDivUp(vars.liquidatedCollatPrice, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif);
        } else {
            vars.seizedAssets =
                vars.repaidUnits.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, vars.liquidatedCollatPrice);
        }

        if (block.timestamp <= obligation.maturity) {
            _checkRecoveryCloseFactor(obligation, collateralIndex, _position, vars, lif);
        }

        uint128 newCollateral = _position.collateral[collateralIndex] - UtilsLib.toUint128(vars.seizedAssets);
        _position.collateral[collateralIndex] = newCollateral;
        if (newCollateral == 0 && vars.seizedAssets > 0) {
            _position.activatedCollaterals = _position.activatedCollaterals.clearBit(collateralIndex);
        }
        _obligationState.withdrawable += UtilsLib.toUint128(vars.repaidUnits);
        _position.debt -= UtilsLib.toUint128(vars.repaidUnits);
    }

    function _checkRecoveryCloseFactor(
        Obligation calldata obligation,
        uint256 collateralIndex,
        Position storage _position,
        LiquidateVars memory vars,
        uint256 lif
    ) internal view {
        uint256 lltv = obligation.collateralParams[collateralIndex].lltv;
        // Rounded up to avoid consecutive max liquidations.
        // Acknowledged that the position could be slightly healthy after a liquidation.
        // Note that debt >= maxDebt in this branch.
        uint256 maxRepaid = lltv < WAD
            ? (_position.debt - vars.maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
            : type(uint256).max;
        require(
            vars.repaidUnits <= maxRepaid
                || _position.collateral[collateralIndex].mulDivDown(
                    vars.liquidatedCollatPrice, ORACLE_PRICE_SCALE
                ).mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < obligation.rcfThreshold,
            "recovery close factor conditions violated"
        );
    }

    /// @dev Passing type(uint256).max cancels all offers in the group (and never reverts).
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        require(amount >= consumed[onBehalf][group], "already consumed");
        consumed[onBehalf][group] = amount;
        emit EventsLib.SetConsumed(msg.sender, onBehalf, group, amount);
    }

    /// @dev TODO: is it safe enough?
    function shuffleSession(address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 newSession = keccak256(abi.encode(session[onBehalf], blockhash(block.number - 1)));
        session[onBehalf] = newSession;
        emit EventsLib.ShuffleSession(msg.sender, onBehalf, newSession);
    }

    /// @dev Authorized addresses can authorize other addresses to act on their behalf so it should be used carefully.
    function setIsAuthorized(address onBehalf, address authorized, bool newIsAuthorized) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        isAuthorized[onBehalf][authorized] = newIsAuthorized;
        emit EventsLib.SetIsAuthorized(msg.sender, onBehalf, authorized, newIsAuthorized);
    }

    function flashLoan(address token, uint256 assets, address callback, bytes calldata data) external {
        emit EventsLib.FlashLoan(msg.sender, token, assets);
        SafeTransferLib.safeTransfer(token, msg.sender, assets);
        IFlashLoanCallback(callback).onFlashLoan(token, assets, data);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), assets);
    }

    /// @dev Returns the obligation id and creates the obligation if it doesn't exist yet.
    function touchObligation(Obligation memory obligation) public returns (bytes32) {
        bytes32 id = toId(obligation);
        if (!_obligationStates[id].created) {
            require(obligation.collateralParams.length > 0, "no collateralParams");
            require(obligation.collateralParams.length <= MAX_COLLATERALS, "too many collateralParams");
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
                address collateralToken = obligation.collateralParams[i].token;
                require(collateralToken > previousCollateralToken, "collateralParams not sorted");
                uint256 lltv = obligation.collateralParams[i].lltv;
                require(isLltvAllowed(lltv), "lltv not allowed");
                require(
                    obligation.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_LOW)
                        || obligation.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_HIGH),
                    "invalid maxLif"
                );
                previousCollateralToken = collateralToken;
            }

            ObligationState storage _obligationState = _obligationStates[id];
            _obligationState.created = true;
            uint16[7] memory _defaultTradingFees = defaultTradingFees[obligation.loanToken];
            _obligationState.fee0 = _defaultTradingFees[0];
            _obligationState.fee1 = _defaultTradingFees[1];
            _obligationState.fee2 = _defaultTradingFees[2];
            _obligationState.fee3 = _defaultTradingFees[3];
            _obligationState.fee4 = _defaultTradingFees[4];
            _obligationState.fee5 = _defaultTradingFees[5];
            _obligationState.fee6 = _defaultTradingFees[6];
            _obligationState.continuousFee = defaultContinuousFee[obligation.loanToken];
            IdLib.storeInCode(obligation);

            emit EventsLib.ObligationCreated(id, obligation);
        }
        return id;
    }

    /// SLASHING AND CONTINUOUS FEE ACCRUAL ///

    /// @dev Expects the id to correspond to the obligation's id.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function updatePositionView(Obligation memory obligation, bytes32 id, address user)
        public
        view
        returns (uint128, uint128, uint128)
    {
        Position storage _position = position[id][user];
        SlashResult memory slash = _computeSlash(_position, _obligationStates[id].lossIndex);
        uint256 accrualEnd = UtilsLib.min(block.timestamp, obligation.maturity);
        uint128 _lastAccrual = _position.lastAccrual;
        // forge-lint: disable-next-item(unsafe-typecast) as fee <= pending <= credit which are uint128 position fields
        uint128 fee = _lastAccrual < obligation.maturity
            ? uint128(uint256(slash.postSlashPending).mulDivDown(accrualEnd - _lastAccrual, obligation.maturity - _lastAccrual))
            : 0;
        return (slash.postSlashCredit - fee, slash.postSlashPending - fee, fee);
    }

    function _computeSlash(Position storage _position, uint128 oblLossIndex)
        internal
        view
        returns (SlashResult memory)
    {
        uint128 credit = _position.credit;
        uint128 _lossIndex = _position.lossIndex;
        uint256 postSlashCredit = _lossIndex < type(uint128).max
            ? credit.mulDivDown(type(uint128).max - oblLossIndex, type(uint128).max - _lossIndex)
            : 0;
        uint128 _pendingFee = _position.pendingFee;
        uint256 postSlashPending = credit > 0 ? _pendingFee - _pendingFee.mulDivUp(credit - postSlashCredit, credit) : 0;
        // forge-lint: disable-next-item(unsafe-typecast) as credit and pending are <= uint128 position fields
        return SlashResult(uint128(postSlashCredit), uint128(postSlashPending));
    }

    /// @dev Slashes the position and accrues the continuous fee.
    function updatePosition(Obligation memory obligation, address user) external {
        bytes32 id = toId(obligation);
        require(_obligationStates[id].created, "obligation not created");
        _updatePosition(obligation, id, user);
    }

    /// @dev Expects the obligation to be touched.
    /// @dev Expects the id to correspond to the obligation's id.
    function _updatePosition(Obligation memory obligation, bytes32 id, address user) internal {
        Position storage _position = position[id][user];
        (uint128 newCredit, uint128 newPendingFee, uint128 accruedFee) = updatePositionView(obligation, id, user);

        uint128 creditDecrease = _position.credit - newCredit;
        uint128 pendingFeeDecrease = _position.pendingFee - newPendingFee;

        _position.credit = newCredit;
        _position.lossIndex = _obligationStates[id].lossIndex;
        _position.pendingFee = newPendingFee;
        _position.lastAccrual = uint128(block.timestamp);
        _obligationStates[id].continuousFeeCredit += UtilsLib.toUint128(accruedFee);

        emit EventsLib.UpdatePosition(id, user, creditDecrease, pendingFeeDecrease, accruedFee);
    }

    function hasCredit(bytes32 id, address user) internal view returns (bool) {
        return position[id][user].credit > 0;
    }

    /// OTHER VIEW FUNCTIONS ///

    function userLossIndex(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lossIndex;
    }

    function activatedCollaterals(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].activatedCollaterals;
    }

    function collateral(bytes32 id, address user, uint256 index) external view returns (uint128) {
        return position[id][user].collateral[index];
    }

    function toId(Obligation memory obligation) public view returns (bytes32) {
        return IdLib.toId(obligation, block.chainid, address(this));
    }

    /// @dev Reverts if the id is not a valid id of a touched obligation.
    /// @dev Returns the obligation corresponding to the given id.
    function toObligation(bytes32 id) external view returns (Obligation memory) {
        require(_obligationStates[id].created, "obligation not created");
        address create2Address = address(uint160(uint256(id)));
        return abi.decode(create2Address.code, (Obligation));
    }

    function creditOf(bytes32 id, address user) external view returns (uint256) {
        return position[id][user].credit;
    }

    function debtOf(bytes32 id, address user) external view returns (uint256) {
        return position[id][user].debt;
    }

    function totalUnits(bytes32 id) external view returns (uint256) {
        return _obligationStates[id].totalUnits;
    }

    function lossIndex(bytes32 id) external view returns (uint128) {
        return _obligationStates[id].lossIndex;
    }

    function obligationCreated(bytes32 id) external view returns (bool) {
        return _obligationStates[id].created;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return _obligationStates[id].withdrawable;
    }

    function tradingFees(bytes32 id) external view returns (uint16[7] memory) {
        return [
            _obligationStates[id].fee0,
            _obligationStates[id].fee1,
            _obligationStates[id].fee2,
            _obligationStates[id].fee3,
            _obligationStates[id].fee4,
            _obligationStates[id].fee5,
            _obligationStates[id].fee6
        ];
    }

    function continuousFee(bytes32 id) external view returns (uint32) {
        return _obligationStates[id].continuousFee;
    }

    function continuousFeeCredit(bytes32 id) external view returns (uint256) {
        return _obligationStates[id].continuousFeeCredit;
    }

    function pendingFee(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].pendingFee;
    }

    function lastAccrual(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lastAccrual;
    }

    function liquidationLocked(bytes32 id, address user) public view returns (bool) {
        return UtilsLib.tGet(LIQUIDATION_LOCK_SLOT, id, user);
    }

    /// @dev A borrower is liquidatable if they have debt, liquidation is not transiently locked, and they are
    /// past maturity or not healthy.
    function isLiquidatable(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        return position[id][borrower].debt > 0 && !liquidationLocked(id, borrower)
            && (block.timestamp > obligation.maturity || !isHealthy(obligation, id, borrower));
    }

    /// @dev This function should be called with the id corresponding to the obligation.
    /// @dev This function does not call any oracle if debt is 0.
    /// @dev Expects the id to correspond to the obligation's id.
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        uint128 bitmap = _position.activatedCollaterals;
        while (maxDebt < debt && bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            CollateralParams memory collateralParam = obligation.collateralParams[i];
            uint256 price = IOracle(collateralParam.oracle).price();
            maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE)
                .mulDivDown(collateralParam.lltv, WAD);
            bitmap = bitmap.clearBit(i);
        }
        return maxDebt >= debt;
    }

    /// @dev Returns the max LIF for the given lltv and cursor.
    function maxLif(uint256 lltv, uint256 cursor) public pure returns (uint256) {
        return WAD.mulDivDown(WAD, WAD - cursor.mulDivDown(WAD - lltv, WAD));
    }

    /// @dev Returns the max trading fee for the given index.
    function maxTradingFee(uint256 index) public pure returns (uint256) {
        return [0.000014e18, 0.000014e18, 0.000098e18, 0.000417e18, 0.00125e18, 0.0025e18, 0.005e18][index];
    }

    /// @dev Returns the trading fee using piecewise linear interpolation between breakpoints.
    function tradingFee(bytes32 id, uint256 timeToMaturity) public view returns (uint256) {
        ObligationState storage _obligationState = _obligationStates[id];
        require(_obligationState.created, "obligation not created");

        if (timeToMaturity >= 360 days) return _obligationState.fee6 * FEE_STEP;

        // forgefmt: disable-start
        (uint256 start, uint256 end, uint256 feeLower, uint256 feeUpper) =
            timeToMaturity < 1 days   ? (  0 days,   1 days, _obligationState.fee0 * FEE_STEP, _obligationState.fee1 * FEE_STEP) :
            timeToMaturity < 7 days   ? (  1 days,   7 days, _obligationState.fee1 * FEE_STEP, _obligationState.fee2 * FEE_STEP) :
            timeToMaturity < 30 days  ? (  7 days,  30 days, _obligationState.fee2 * FEE_STEP, _obligationState.fee3 * FEE_STEP) :
            timeToMaturity < 90 days  ? ( 30 days,  90 days, _obligationState.fee3 * FEE_STEP, _obligationState.fee4 * FEE_STEP) :
            timeToMaturity < 180 days ? ( 90 days, 180 days, _obligationState.fee4 * FEE_STEP, _obligationState.fee5 * FEE_STEP) :
                                        (180 days, 360 days, _obligationState.fee5 * FEE_STEP, _obligationState.fee6 * FEE_STEP);
        // forgefmt: disable-end

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
