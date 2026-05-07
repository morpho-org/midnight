// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {IdLib} from "./libraries/IdLib.sol";
import {TickLib} from "./libraries/TickLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
// forge-lint: disable-next-item(unaliased-plain-import)
import "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMidnight, Obligation, Offer, CollateralParams, ObligationState, Position} from "./interfaces/IMidnight.sol";
import {
    IBuyCallback,
    ISellCallback,
    ILiquidateCallback,
    IRepayCallback,
    IFlashLoanCallback
} from "./interfaces/ICallbacks.sol";
import {IRatifier} from "./interfaces/IRatifier.sol";
import {IEnterGate, ILiquidatorGate} from "./interfaces/IGate.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// OBLIGATIONS
/// @dev The following constraints are enforced on obligation creation (in touchObligation):
/// - maturity <= block.timestamp + 100 years: the obligation must have a maturity that is not too far in the future.
/// - collateralParams.length > 0: at least one collateral is required.
/// - collateralParams.length <= MAX_COLLATERALS (128): at most 128 collateralParams per obligation.
/// - Collateral tokens must be non-zero and strictly sorted by address (ascending, no duplicates).
/// - Each collateral's lltv must be one of the allowed tiers (see isLltvAllowed in ConstantsLib).
/// - Each collateral's maxLif must equal maxLif(lltv, LIQUIDATION_CURSOR_LOW) or
///   maxLif(lltv, LIQUIDATION_CURSOR_HIGH).
/// @dev Additionally, within a single obligation, a borrower can use at most MAX_COLLATERALS_PER_BORROWER (10)
/// collaterals simultaneously.
///
/// MULTICOLLATS
/// @dev A borrower can `supplyCollateral` and `withdrawCollateral` at any time, subject only to an instantaneous
/// health check on withdrawal. In particular, the borrowers of multicollat obligations can completely
/// change their collateral composition.
/// @dev Liquidation iterates over all activated collaterals and reverts if any of their oracles reverts (see LIVENESS).
/// A single reverting oracle blocks liquidation for every borrower with that collateral activated, and a borrower can
/// activate such a collateral post-incident to block their own liquidation.
/// @dev The oracle-quoted liquidator incentive (i.e., maxRepayable * (LIF-1)) might not be constant across activated
/// collaterals. Hence, liquidators may have a preference order over collaterals when liquidating.
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
/// @dev The fee is tracked per lender via pendingFee in each position. If the obligation's continuous fee changes, the
/// pending fee of existing lenders is not updated (=> their fee is fixed).
/// @dev Absent bad debt, the face value of a lender's position is credit - pendingFee.
///
/// LIQUIDATIONS
/// @dev Accounts are liquidatable only if the liquidation is not locked and they are either unhealthy or the maturity
/// has passed.
/// @dev Liquidations can revert for other reasons, see LIVENESS.
/// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to maxLif at maturity + TIME_TO_MAX_LIF.
/// @dev Before or at maturity, the liquidation cannot put the borrower back into health (recovery close factor), unless
/// the liquidation could leave a collateral with a value that would not be enough to repay rcfThreshold units.
/// @dev The "recovery close factor" (RCF) limits the amount that can be liquidated. In particular, it prevents the
/// liquidation from putting the borrower back into health. Which means (omitting scaling and roundings):
///   newDebt >= newMaxDebt <=> debtOf - repaidUnits >= maxDebt - repaidUnits*LIF*LLTV
///                         <=> repaidUnits <= (debtOf-maxDebt) / (1 - LIF*LLTV).
/// The maxRepaid computation is rounded up to avoid consecutive max liquidations, so the position could be slightly
/// healthy after a liquidation.
/// @dev The RCF is deactivated after the maturity.
/// @dev The RCF is deactivated for small collateral amount, essentially to mitigate issues with liquidations that are
/// too small compared to the gas cost. More precisely, it is deactivated if the liquidation could leave a collateral
/// with a value that would not be enough to repay rcfThreshold units. Which means (omitting scaling and roundings):
///   minNewCollateral * liquidatedCollatPrice / LIF < rcfThreshold
///     <=> (collateral - maxRepaid * LIF / liquidatedCollatPrice) * liquidatedCollatPrice / LIF < rcfThreshold
///     <=> collateral * liquidatedCollatPrice / LIF - maxRepaid < rcfThreshold
///
/// SLASHING
/// @dev When some bad debt is realized, it is socialized among lenders in the obligation.
/// @dev At each lender's next interaction, their credit is slashed proportionally.
///
/// GROUPS
/// @dev Groups are useful to have a global offered amount shared across multiple offers ("OCO").
/// @dev To work as expected, all offers in the same group should have the same max values and loan token.
/// @dev Only one of maxSellerAssets, maxBuyerAssets, or maxUnits can be nonzero per offer.
///
/// SESSION
/// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
/// @dev Offers should have the current session to be valid.
///
/// ROOT
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev If the offers are well-sorted (such that for all nodes, hash(left) <= hash(right)) when given to the wallet,
/// the EIP-712 digest will match the root of the tree. This allows to have clear signing of the tree, credits to
/// Seaport for this mechanism.
///
/// AUTHORIZATIONS
/// @dev All functions that change the position, session, consumed and authorization are accessible to the user and to
/// any account that has been authorized. Thus, to scope authorizations one should authorize a smart-contract with
/// scoped behavior.
/// @dev When authorizing a smart-contract, one should consider:
/// - The targets/functions that the account can call. At least Midnight's functions should be considered, but other
/// contracts might re-use Midnight's authorization mapping too (e.g ratifiers and authorizers). In particular,
/// authorized accounts can authorize other accounts on behalf of the user.
/// - Under which conditions the account can return CALLBACK_SUCCESS when its onRatify function is called.
/// @dev updatePosition and liquidate (for liquidatable users) also impact the position and are permissionless.
///
/// ROUNDINGS
/// @dev Because of roundings, trading and continuous fees might charge less than expected, which can become problematic
/// for chains where the gas is cheaper than 1 asset of the loan token.
/// @dev lossFactor is rounded up so lenders collectively lose a bit more on each bad debt realization.
/// @dev slash rounds the credit down, so lenders lose a bit at each interaction.
/// @dev If an obligation loses almost all of its value to bad debt over its lifetime, then the accounting of the loss
/// may become extremely imprecise (against the user), potentially leading to a total loss. In those cases the
/// obligation doesn't function properly, and notably the take function reverts when the loss factor is maxed out.
/// GATES
/// @dev Gates are optional (address(0) = unrestricted).
/// @dev The entry gate can prevent entry actions (increasing credit or debt) in the obligation.
/// @dev In particular, it does not prevent the user from exiting the obligation even when the entry gate is reverting.
/// @dev The liquidator gate can prevent the user from liquidating borrowers in the obligation (and realizing bad debt).
///
/// TOKEN SAFETY REQUIREMENTS
/// @dev List of assumptions on tokens that guarantee that Midnight behaves as expected:
/// - It should be ERC-20 compliant, except that it can omit return values on transfer and transferFrom. In particular,
/// it should not revert because a transfer is no-op.
/// - Midnight's balance of the token should only decrease on transfer and transferFrom.
/// - It should not re-enter Midnight on transfer nor transferFrom.
/// - Midnight must send/receive exactly the requested amount on transfers.
/// @dev See LIVENESS for liveness guarantees.
///
/// LIVENESS
/// @dev If an activated collateral oracle reverts on price, liquidate reverts.
/// @dev If an activated collateral oracle reverts on price, isHealthy, withdrawCollateral and take revert when the user
/// (seller for take) has non-zero debt.
/// @dev If the liquidated collateral oracle returns 0 on price, liquidate with repaid input reverts.
/// @dev If an activated collateral oracle returns a price such that the user's collateral quoted in loan token is
/// greater than type(uint128).max, then liquidate, isHealthy, withdrawCollateral when the borrower has debt, and take
/// whenever the seller still has debt could all revert.
/// @dev If enterGate.canIncreaseCredit reverts or returns false, take reverts if the buyer's credit increases.
/// @dev If enterGate.canIncreaseDebt reverts or returns false, take reverts if the seller's debt increases.
/// @dev If liquidatorGate reverts or returns false on canLiquidate, liquidate reverts.
/// @dev If a token pulled by Midnight reverts or returns false on transferFrom despite balances and approvals being
/// right, take, repay, supplyCollateral, liquidate, and flashLoan repayment revert when they need to pull that token.
/// @dev If a token sent by Midnight reverts or returns false on transfer despite balances being right, withdraw,
/// withdrawCollateral, fee claims, the collateral leg of liquidate, and flashLoan revert when they need to send that
/// token.
/// @dev If a callback reverts or returns something other than CALLBACK_SUCCESS, take, repay, liquidate, and flashLoan
/// revert.
///
/// ROLES
/// @dev The role setter can set the role setter, fee setter, and fee claimer.
/// @dev The fee setter can set the default and per-obligation trading fee and continuous fee.
/// @dev The fee claimer can claim the trading fee and continuous fee.
/// @dev When the claimer is set, the old claimer loses the unclaimed fees.
///
/// MISC
/// @dev creditOf, pendingFee, and lossFactor are not up to date. One must use updatePositionView to get the up to date
/// values.
/// @dev The max amount of totalUnits, collateral, credit, and debt is type(uint128).max (~1e38).
/// @dev Zero checks are not systematically performed.
/// @dev No-ops are allowed. In particular, Midnight can call the callback of offers through a no-op take, even if those
/// offers are "filled" (consumed=max).
/// @dev NatSpec comments are included only when they bring clarity.
/// @dev INITIAL_CHAIN_ID is captured at construction and used in place of block.chainid when computing obligation ids,
/// so a hard fork that changes block.chainid does not strand existing accounting. But as a result, after a hard-fork
/// there can be some obligation id clashes.
/// @dev The case LLTV=WAD is special, and should be used with care, notably:
/// - It has no overcollateralization, so unhealthy positions will almost always realize bad debt when liquidated. In
/// particular, the RCF is "inactive", meaning liquidations can always liquidate everything.
/// - It has no liquidation incentive, so liquidators repay at exactly the oracle price (plus roundings).
/// @dev Relies on the clz opcode (Osaka), on the mcopy, tload, and tstore opcodes (Cancun), and on the push0 opcode
/// (Shanghai).
///
contract Midnight is IMidnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// IMMUTABLES ///

    uint256 public immutable INITIAL_CHAIN_ID;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => Position)) public position;
    mapping(bytes32 id => ObligationState) public obligationState;
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
        INITIAL_CHAIN_ID = block.chainid;
        emit EventsLib.Constructor(msg.sender, INITIAL_CHAIN_ID);
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
        require(msg.sender == roleSetter, OnlyRoleSetter());
        roleSetter = newRoleSetter;
        emit EventsLib.SetRoleSetter(newRoleSetter);
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == roleSetter, OnlyRoleSetter());
        feeSetter = newFeeSetter;
        emit EventsLib.SetFeeSetter(newFeeSetter);
    }

    function setFeeClaimer(address newFeeClaimer) external {
        require(msg.sender == roleSetter, OnlyRoleSetter());
        feeClaimer = newFeeClaimer;
        emit EventsLib.SetFeeClaimer(newFeeClaimer);
    }

    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        ObligationState storage _obligationState = obligationState[id];
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(index <= 6, InvalidFeeIndex());
        require(newTradingFee <= maxTradingFee(index), TradingFeeTooHigh());
        require(newTradingFee % FEE_STEP == 0, FeeNotMultipleOfFeeStep());
        require(_obligationState.created, ObligationNotCreated());
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        uint16 toStore = uint16(newTradingFee / FEE_STEP);
        if (index == 0) _obligationState.tradingFee0 = toStore;
        else if (index == 1) _obligationState.tradingFee1 = toStore;
        else if (index == 2) _obligationState.tradingFee2 = toStore;
        else if (index == 3) _obligationState.tradingFee3 = toStore;
        else if (index == 4) _obligationState.tradingFee4 = toStore;
        else if (index == 5) _obligationState.tradingFee5 = toStore;
        else if (index == 6) _obligationState.tradingFee6 = toStore;
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(index <= 6, InvalidFeeIndex());
        require(newTradingFee <= maxTradingFee(index), TradingFeeTooHigh());
        require(newTradingFee % FEE_STEP == 0, FeeNotMultipleOfFeeStep());
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        defaultTradingFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setObligationContinuousFee(bytes32 id, uint256 newContinuousFee) external {
        ObligationState storage _obligationState = obligationState[id];
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, ContinuousFeeTooHigh());
        require(_obligationState.created, ObligationNotCreated());
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        _obligationState.continuousFee = uint32(newContinuousFee);
        emit EventsLib.SetObligationContinuousFee(id, newContinuousFee);
    }

    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, ContinuousFeeTooHigh());
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        defaultContinuousFee[loanToken] = uint32(newContinuousFee);
        emit EventsLib.SetDefaultContinuousFee(loanToken, newContinuousFee);
    }

    function claimTradingFee(address token, uint256 amount, address receiver) external {
        require(msg.sender == feeClaimer, OnlyFeeClaimer());
        claimableTradingFee[token] -= amount;
        emit EventsLib.ClaimTradingFee(msg.sender, token, amount, receiver);
        SafeTransferLib.safeTransfer(token, receiver, amount);
    }

    function claimContinuousFee(Obligation memory obligation, uint256 amount, address receiver) external {
        bytes32 id = toId(obligation);
        ObligationState storage _obligationState = obligationState[id];
        require(msg.sender == feeClaimer, OnlyFeeClaimer());
        require(_obligationState.created, ObligationNotCreated());

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
    /// @dev The taker might not get the price they expected if the trading fee was just changed. A bundler can be used
    /// to perform atomic price checks.
    /// @dev Taking buy offers with price < trading fee will revert.
    /// @dev In particular, if the trading fee gets increased, it might implicitely cancel offers with very low price.
    /// @dev All sellerAssets are reachable with the units input, and all buyerAssets are reachable only if buyerPrice
    /// <= WAD.
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
        require(taker == msg.sender || isAuthorized[taker][msg.sender], TakerUnauthorized());
        bytes32 id = touchObligation(offer.obligation);
        ObligationState storage _obligationState = obligationState[id];
        require(_obligationState.lossFactor < type(uint128).max, ObligationLossFactorMaxedOut());
        require(
            UtilsLib.atMostOneNonZero(offer.maxSellerAssets, offer.maxBuyerAssets, offer.maxUnits), MultipleNonZero()
        );
        require(block.timestamp >= offer.start, OfferNotStarted());
        require(block.timestamp <= offer.expiry, OfferExpired());
        require(offer.maker != taker, SelfTake());
        require(UtilsLib.isLeaf(root, UtilsLib.hashOffer(offer), proof), InvalidProof());
        require(offer.session == session[offer.maker], InvalidSession());
        require(isAuthorized[offer.maker][offer.ratifier], RatifierUnauthorized());
        require(IRatifier(offer.ratifier).onRatify(offer, root, ratifierData) == CALLBACK_SUCCESS, RatifierFail());

        (address buyer, address seller) = offer.buy ? (offer.maker, taker) : (taker, offer.maker);

        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        uint256 _tradingFee = tradingFee(id, timeToMaturity);
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        uint256 buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD);
        uint256 sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD);

        uint256 newConsumed;
        if (offer.maxSellerAssets > 0) {
            newConsumed = consumed[offer.maker][offer.group] += sellerAssets;
            require(newConsumed <= offer.maxSellerAssets, ConsumedSellerAssets());
        } else if (offer.maxBuyerAssets > 0) {
            newConsumed = consumed[offer.maker][offer.group] += buyerAssets;
            require(newConsumed <= offer.maxBuyerAssets, ConsumedBuyerAssets());
        } else {
            newConsumed = consumed[offer.maker][offer.group] += units;
            require(newConsumed <= offer.maxUnits, ConsumedUnits());
        }

        Position storage buyerPos = position[id][buyer];
        Position storage sellerPos = position[id][seller];

        if (hasCredit(id, buyer) || units > buyerPos.debt) _updatePosition(offer.obligation, id, buyer);
        if (hasCredit(id, seller)) _updatePosition(offer.obligation, id, seller);

        uint256 buyerCreditIncrease = UtilsLib.zeroFloorSub(units, buyerPos.debt);
        uint256 sellerCreditDecrease = UtilsLib.min(units, sellerPos.credit);
        uint256 sellerDebtIncrease = units - sellerCreditDecrease;
        uint128 buyerPendingFeeIncrease =
            UtilsLib.toUint128(buyerCreditIncrease.mulDivDown(_obligationState.continuousFee * timeToMaturity, WAD));
        uint128 sellerPendingFeeDecrease = sellerPos.credit > 0
            ? UtilsLib.toUint128(sellerPos.pendingFee.mulDivUp(sellerCreditDecrease, sellerPos.credit))
            : 0;

        buyerPos.debt -= UtilsLib.toUint128(units - buyerCreditIncrease);
        buyerPos.pendingFee += buyerPendingFeeIncrease;
        buyerPos.credit += UtilsLib.toUint128(buyerCreditIncrease);

        sellerPos.pendingFee -= sellerPendingFeeDecrease;
        sellerPos.credit -= UtilsLib.toUint128(sellerCreditDecrease);
        sellerPos.debt += UtilsLib.toUint128(sellerDebtIncrease);

        _obligationState.totalUnits =
            UtilsLib.toUint128(_obligationState.totalUnits + buyerCreditIncrease - sellerCreditDecrease);

        if (offer.reduceOnly) {
            require(offer.buy ? buyerCreditIncrease == 0 : sellerDebtIncrease == 0, MakerCreditOrDebtIncreased());
        }

        require(
            offer.obligation.enterGate == address(0) || buyerCreditIncrease == 0
                || IEnterGate(offer.obligation.enterGate).canIncreaseCredit(buyer),
            BuyerGatedFromIncreasingCredit()
        );
        require(
            offer.obligation.enterGate == address(0) || sellerDebtIncrease == 0
                || IEnterGate(offer.obligation.enterGate).canIncreaseDebt(seller),
            SellerGatedFromIncreasingDebt()
        );

        address buyerCallback = offer.buy ? offer.callback : takerCallback;
        address sellerCallback = offer.buy ? takerCallback : offer.callback;
        address payer = buyerCallback != address(0) ? buyerCallback : (offer.buy ? buyer : msg.sender);
        address receiver = offer.buy ? receiverIfTakerIsSeller : offer.receiverIfMakerIsSeller;

        emit EventsLib.Take(
            msg.sender,
            id,
            offer.maker,
            taker,
            offer.buy,
            buyerAssets,
            sellerAssets,
            units,
            payer,
            receiver,
            offer.group,
            newConsumed,
            buyerPendingFeeIncrease,
            sellerPendingFeeDecrease,
            buyerCreditIncrease,
            sellerCreditDecrease
        );

        bool wasLocked = UtilsLib.tExchange(LIQUIDATION_LOCK_SLOT, id, seller, true);
        if (buyerCallback != address(0)) {
            bytes memory buyerCallbackData = offer.buy ? offer.callbackData : takerCallbackData;
            require(
                IBuyCallback(buyerCallback).onBuy(id, offer.obligation, buyer, buyerAssets, units, buyerCallbackData)
                    == CALLBACK_SUCCESS,
                WrongBuyCallbackReturnValue()
            );
        }

        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, payer, address(this), buyerAssets - sellerAssets);
        claimableTradingFee[offer.obligation.loanToken] += buyerAssets - sellerAssets;
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, payer, receiver, sellerAssets);

        if (sellerCallback != address(0)) {
            bytes memory sellerCallbackData = offer.buy ? takerCallbackData : offer.callbackData;
            require(
                ISellCallback(sellerCallback)
                        .onSell(id, offer.obligation, seller, sellerAssets, units, sellerCallbackData)
                    == CALLBACK_SUCCESS,
                WrongSellCallbackReturnValue()
            );
        }
        if (!wasLocked) UtilsLib.tExchange(LIQUIDATION_LOCK_SLOT, id, seller, false);
        require(
            position[id][seller].debt == 0 || liquidationLocked(id, seller)
                || (block.timestamp <= offer.obligation.maturity && isHealthy(offer.obligation, id, seller)),
            SellerIsLiquidatable()
        );

        return (buyerAssets, sellerAssets, units);
    }

    /// @dev Will revert if there are no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 units, address onBehalf, address receiver) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
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

    function repay(Obligation memory obligation, uint256 units, address onBehalf, address callback, bytes calldata data)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchObligation(obligation);

        position[id][onBehalf].debt -= UtilsLib.toUint128(units);
        obligationState[id].withdrawable += UtilsLib.toUint128(units);

        address payer = callback != address(0) ? callback : msg.sender;
        emit EventsLib.Repay(msg.sender, id, units, onBehalf, payer);

        if (callback != address(0)) {
            require(
                IRepayCallback(callback).onRepay(id, obligation, units, onBehalf, data) == CALLBACK_SUCCESS,
                WrongRepayCallbackReturnValue()
            );
        }
        SafeTransferLib.safeTransferFrom(obligation.loanToken, payer, address(this), units);
    }

    /// @dev This function checks authorization to prevent activated collateral poisoning.
    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collateralParams[collateralIndex].token;

        Position storage _position = position[id][onBehalf];
        uint256 oldCollateral = _position.collateral[collateralIndex];
        _position.collateral[collateralIndex] = UtilsLib.toUint128(oldCollateral + assets);

        if (oldCollateral == 0 && assets > 0) {
            uint128 newCollateralBitmap = _position.collateralBitmap.setBit(collateralIndex);
            _position.collateralBitmap = newCollateralBitmap;
            require(
                UtilsLib.countBits(newCollateralBitmap) <= MAX_COLLATERALS_PER_BORROWER, TooManyActivatedCollaterals()
            );
        }

        emit EventsLib.SupplyCollateral(msg.sender, id, collateralToken, assets, onBehalf);

        SafeTransferLib.safeTransferFrom(collateralToken, msg.sender, address(this), assets);
    }

    /// @dev This function does not call any oracle if the borrower has no debt.
    function withdrawCollateral(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collateralParams[collateralIndex].token;

        Position storage _position = position[id][onBehalf];
        uint256 newCollateral = _position.collateral[collateralIndex] - assets;
        _position.collateral[collateralIndex] = UtilsLib.toUint128(newCollateral);

        if (newCollateral == 0 && assets > 0) {
            _position.collateralBitmap = _position.collateralBitmap.clearBit(collateralIndex);
        }

        require(isHealthy(obligation, id, onBehalf), UnhealthyBorrower());

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateralToken, assets, onBehalf, receiver);

        SafeTransferLib.safeTransfer(collateralToken, receiver, assets);
    }

    /// @dev See LIQUIDATIONS section for more details.
    /// @dev At least one of seizedAssets or repaidUnits should be equal to zero.
    /// @dev Passing both 0 for seizedAssets and repaidUnits allows to realize bad debt with 0 token transferred.
    /// @dev Liquidations with both 0 for seizedAssets and repaidUnits can be done with a collateral that is not
    /// activated.
    /// @dev Returns the seized assets and the repaid units.
    function liquidate(
        Obligation calldata obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        address receiver,
        address callback,
        bytes calldata data
    ) external returns (uint256, uint256) {
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
        Position storage _position = position[id][borrower];
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), InconsistentInput());
        require(
            obligation.liquidatorGate == address(0)
                || ILiquidatorGate(obligation.liquidatorGate).canLiquidate(msg.sender),
            LiquidatorGatedFromLiquidating()
        );

        uint256 maxDebt;
        uint256 liquidatedCollatPrice;
        uint256 originalDebt = _position.debt;
        uint256 badDebt = originalDebt;
        uint128 _collateralBitmap = _position.collateralBitmap;
        while (_collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(_collateralBitmap);
            CollateralParams memory _collateralParam = obligation.collateralParams[i];
            uint256 price = IOracle(_collateralParam.oracle).price();
            if (i == collateralIndex) liquidatedCollatPrice = price;
            uint256 _collateral = _position.collateral[i];
            maxDebt += _collateral.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateralParam.lltv, WAD);
            badDebt = badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
            );
            _collateralBitmap = _collateralBitmap.clearBit(i);
        }

        require(
            originalDebt > 0 && !liquidationLocked(id, borrower)
                && (block.timestamp > obligation.maturity || originalDebt > maxDebt),
            NotLiquidatable()
        );

        if (badDebt > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(badDebt);
            uint256 oldTotalUnits = _obligationState.totalUnits;
            uint256 oldLossFactor = _obligationState.lossFactor;
            _obligationState.lossFactor = UtilsLib.toUint128(
                type(uint128).max
                    - (type(uint128).max - oldLossFactor).mulDivDown(oldTotalUnits - badDebt, oldTotalUnits)
            );
            _obligationState.totalUnits -= UtilsLib.toUint128(badDebt);
            _obligationState.continuousFeeCredit = oldLossFactor < type(uint128).max
                ? UtilsLib.toUint128(
                    _obligationState.continuousFeeCredit
                        .mulDivDown(type(uint128).max - _obligationState.lossFactor, type(uint128).max - oldLossFactor)
                )
                : 0;
        }

        if (repaidUnits > 0 || seizedAssets > 0) {
            uint256 _maxLif = obligation.collateralParams[collateralIndex].maxLif;
            uint256 lif = originalDebt > maxDebt
                ? _maxLif
                : UtilsLib.min(
                    _maxLif, WAD + (_maxLif - WAD) * (block.timestamp - obligation.maturity) / TIME_TO_MAX_LIF
                );

            if (seizedAssets > 0) {
                repaidUnits = seizedAssets.mulDivUp(liquidatedCollatPrice, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif);
            } else {
                seizedAssets = repaidUnits.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, liquidatedCollatPrice);
            }

            if (block.timestamp <= obligation.maturity) {
                uint256 lltv = obligation.collateralParams[collateralIndex].lltv;
                // Note that debt >= maxDebt in this branch.
                uint256 maxRepaid = lltv < WAD
                    ? (_position.debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
                    : type(uint256).max;
                require(
                    repaidUnits <= maxRepaid
                        || _position.collateral[collateralIndex].mulDivDown(liquidatedCollatPrice, ORACLE_PRICE_SCALE)
                            .mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < obligation.rcfThreshold,
                    RecoveryCloseFactorConditionsViolated()
                );
            }

            uint128 newCollateral = _position.collateral[collateralIndex] - UtilsLib.toUint128(seizedAssets);
            _position.collateral[collateralIndex] = newCollateral;
            if (newCollateral == 0 && seizedAssets > 0) {
                _position.collateralBitmap = _position.collateralBitmap.clearBit(collateralIndex);
            }
            _obligationState.withdrawable += UtilsLib.toUint128(repaidUnits);
            _position.debt -= UtilsLib.toUint128(repaidUnits);
        }

        address payer = callback != address(0) ? callback : msg.sender;

        emit EventsLib.Liquidate(
            msg.sender,
            id,
            obligation.collateralParams[collateralIndex].token,
            seizedAssets,
            repaidUnits,
            borrower,
            badDebt,
            _obligationState.lossFactor,
            payer,
            receiver
        );

        SafeTransferLib.safeTransfer(obligation.collateralParams[collateralIndex].token, receiver, seizedAssets);

        if (callback != address(0)) {
            require(
                ILiquidateCallback(callback)
                    .onLiquidate(id, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data)
                == CALLBACK_SUCCESS,
                WrongLiquidateCallbackReturnValue()
            );
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, payer, address(this), repaidUnits);

        return (seizedAssets, repaidUnits);
    }

    /// @dev Passing type(uint256).max cancels all offers in the group (and never reverts).
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        require(amount >= consumed[onBehalf][group], AlreadyConsumed());
        consumed[onBehalf][group] = amount;
        emit EventsLib.SetConsumed(msg.sender, onBehalf, group, amount);
    }

    /// @dev TODO: is it safe enough?
    function shuffleSession(address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 newSession = keccak256(abi.encode(session[onBehalf], blockhash(block.number - 1)));
        session[onBehalf] = newSession;
        emit EventsLib.ShuffleSession(msg.sender, onBehalf, newSession);
    }

    /// @dev See Authorization section above.
    function setIsAuthorized(address onBehalf, address authorized, bool newIsAuthorized) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        isAuthorized[onBehalf][authorized] = newIsAuthorized;
        emit EventsLib.SetIsAuthorized(msg.sender, onBehalf, authorized, newIsAuthorized);
    }

    function flashLoan(address[] calldata tokens, uint256[] calldata assets, address callback, bytes calldata data)
        external
    {
        require(tokens.length == assets.length, InconsistentInput());
        emit EventsLib.FlashLoan(msg.sender, tokens, assets, callback);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeTransferLib.safeTransfer(tokens[i], callback, assets[i]);
        }
        require(
            IFlashLoanCallback(callback).onFlashLoan(tokens, assets, data) == CALLBACK_SUCCESS,
            WrongFlashLoanCallbackReturnValue()
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeTransferLib.safeTransferFrom(tokens[i], callback, address(this), assets[i]);
        }
    }

    /// @dev Returns the obligation id and creates the obligation if it doesn't exist yet.
    function touchObligation(Obligation memory obligation) public returns (bytes32) {
        bytes32 id = toId(obligation);
        if (!obligationState[id].created) {
            require(obligation.maturity <= block.timestamp + 100 * 365 days, MaturityTooFar());
            require(obligation.collateralParams.length > 0, NoCollateralParams());
            require(obligation.collateralParams.length <= MAX_COLLATERALS, TooManyCollateralParams());
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
                address collateralToken = obligation.collateralParams[i].token;
                require(collateralToken > previousCollateralToken, CollateralParamsNotSorted());
                uint256 lltv = obligation.collateralParams[i].lltv;
                require(isLltvAllowed(lltv), LltvNotAllowed());
                require(
                    obligation.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_LOW)
                        || obligation.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_HIGH),
                    InvalidMaxLif()
                );
                previousCollateralToken = collateralToken;
            }

            ObligationState storage _obligationState = obligationState[id];
            _obligationState.created = true;
            uint16[7] memory _defaultTradingFees = defaultTradingFees[obligation.loanToken];
            _obligationState.tradingFee0 = _defaultTradingFees[0];
            _obligationState.tradingFee1 = _defaultTradingFees[1];
            _obligationState.tradingFee2 = _defaultTradingFees[2];
            _obligationState.tradingFee3 = _defaultTradingFees[3];
            _obligationState.tradingFee4 = _defaultTradingFees[4];
            _obligationState.tradingFee5 = _defaultTradingFees[5];
            _obligationState.tradingFee6 = _defaultTradingFees[6];
            _obligationState.continuousFee = defaultContinuousFee[obligation.loanToken];
            IdLib.storeInCode(obligation, INITIAL_CHAIN_ID);

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
        uint128 credit = _position.credit;
        uint128 _lossFactor = _position.lossFactor;
        uint256 postSlashCredit = _lossFactor < type(uint128).max
            ? credit.mulDivDown(type(uint128).max - obligationState[id].lossFactor, type(uint128).max - _lossFactor)
            : 0;
        uint128 _pendingFee = _position.pendingFee;
        uint256 postSlashPending = credit > 0 ? _pendingFee - _pendingFee.mulDivUp(credit - postSlashCredit, credit) : 0;
        uint256 accrualEnd = UtilsLib.min(block.timestamp, obligation.maturity);
        uint128 _lastAccrual = _position.lastAccrual;
        // forge-lint: disable-next-item(unsafe-typecast) as fee <= pending <= credit which are uint128 position fields
        uint128 fee = _lastAccrual < obligation.maturity
            ? uint128(postSlashPending.mulDivDown(accrualEnd - _lastAccrual, obligation.maturity - _lastAccrual))
            : 0;
        // forge-lint: disable-next-item(unsafe-typecast) as credit and pending are <= uint128 position fields
        return (uint128(postSlashCredit) - fee, uint128(postSlashPending) - fee, fee);
    }

    /// @dev Slashes the position and accrues the continuous fee.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function updatePosition(Obligation memory obligation, address user) external returns (uint128, uint128, uint128) {
        bytes32 id = toId(obligation);
        require(obligationState[id].created, ObligationNotCreated());
        return _updatePosition(obligation, id, user);
    }

    /// @dev Expects the obligation to be touched.
    /// @dev Expects the id to correspond to the obligation's id.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function _updatePosition(Obligation memory obligation, bytes32 id, address user)
        internal
        returns (uint128, uint128, uint128)
    {
        Position storage _position = position[id][user];
        (uint128 newCredit, uint128 newPendingFee, uint128 accruedFee) = updatePositionView(obligation, id, user);

        uint128 creditDecrease = _position.credit - newCredit;
        uint128 pendingFeeDecrease = _position.pendingFee - newPendingFee;

        _position.credit = newCredit;
        _position.lossFactor = obligationState[id].lossFactor;
        _position.pendingFee = newPendingFee;
        _position.lastAccrual = uint128(block.timestamp);
        obligationState[id].continuousFeeCredit += UtilsLib.toUint128(accruedFee);

        emit EventsLib.UpdatePosition(id, user, creditDecrease, pendingFeeDecrease, accruedFee);

        return (newCredit, newPendingFee, accruedFee);
    }

    function hasCredit(bytes32 id, address user) internal view returns (bool) {
        return position[id][user].credit > 0;
    }

    /// OTHER VIEW FUNCTIONS ///

    function userLossFactor(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lossFactor;
    }

    function collateralBitmap(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].collateralBitmap;
    }

    function collateral(bytes32 id, address user, uint256 index) external view returns (uint128) {
        return position[id][user].collateral[index];
    }

    function toId(Obligation memory obligation) public view returns (bytes32) {
        return IdLib.toId(obligation, INITIAL_CHAIN_ID, address(this));
    }

    /// @dev Reverts if the id is not a valid id of a touched obligation.
    /// @dev Returns the obligation corresponding to the given id.
    function toObligation(bytes32 id) external view returns (Obligation memory) {
        require(obligationState[id].created, ObligationNotCreated());
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
        return obligationState[id].totalUnits;
    }

    function lossFactor(bytes32 id) external view returns (uint128) {
        return obligationState[id].lossFactor;
    }

    function obligationCreated(bytes32 id) external view returns (bool) {
        return obligationState[id].created;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return obligationState[id].withdrawable;
    }

    function tradingFees(bytes32 id) external view returns (uint16[7] memory) {
        return [
            obligationState[id].tradingFee0,
            obligationState[id].tradingFee1,
            obligationState[id].tradingFee2,
            obligationState[id].tradingFee3,
            obligationState[id].tradingFee4,
            obligationState[id].tradingFee5,
            obligationState[id].tradingFee6
        ];
    }

    function continuousFee(bytes32 id) external view returns (uint32) {
        return obligationState[id].continuousFee;
    }

    function continuousFeeCredit(bytes32 id) external view returns (uint256) {
        return obligationState[id].continuousFeeCredit;
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

    /// @dev This function should be called with the id corresponding to the obligation.
    /// @dev This function does not call any oracle if debt is 0.
    /// @dev Expects the id to correspond to the obligation's id.
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        if (debt > 0) {
            uint128 _collateralBitmap = _position.collateralBitmap;
            while (_collateralBitmap != 0) {
                uint256 i = UtilsLib.msb(_collateralBitmap);
                CollateralParams memory collateralParam = obligation.collateralParams[i];
                uint256 price = IOracle(collateralParam.oracle).price();
                maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE)
                    .mulDivDown(collateralParam.lltv, WAD);
                _collateralBitmap = _collateralBitmap.clearBit(i);
            }
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
        ObligationState storage _obligationState = obligationState[id];
        require(_obligationState.created, ObligationNotCreated());

        if (timeToMaturity >= 360 days) return _obligationState.tradingFee6 * FEE_STEP;

        // forgefmt: disable-start
        (uint256 start, uint256 end, uint256 feeLower, uint256 feeUpper) =
            timeToMaturity < 1 days   ? (  0 days,   1 days, _obligationState.tradingFee0 * FEE_STEP, _obligationState.tradingFee1 * FEE_STEP) :
            timeToMaturity < 7 days   ? (  1 days,   7 days, _obligationState.tradingFee1 * FEE_STEP, _obligationState.tradingFee2 * FEE_STEP) :
            timeToMaturity < 30 days  ? (  7 days,  30 days, _obligationState.tradingFee2 * FEE_STEP, _obligationState.tradingFee3 * FEE_STEP) :
            timeToMaturity < 90 days  ? ( 30 days,  90 days, _obligationState.tradingFee3 * FEE_STEP, _obligationState.tradingFee4 * FEE_STEP) :
            timeToMaturity < 180 days ? ( 90 days, 180 days, _obligationState.tradingFee4 * FEE_STEP, _obligationState.tradingFee5 * FEE_STEP) :
                                        (180 days, 360 days, _obligationState.tradingFee5 * FEE_STEP, _obligationState.tradingFee6 * FEE_STEP);
        // forgefmt: disable-end

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
