// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {IdLib} from "./libraries/IdLib.sol";
import {TickLib} from "./libraries/TickLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol"; // forge-lint: disable-line(unaliased-plain-import)
import "./interfaces/ICallbacks.sol"; // forge-lint: disable-line(unaliased-plain-import)
import {IOracle} from "./interfaces/IOracle.sol";
import {IRatifier} from "./interfaces/IRatifier.sol";
import {IEnterGate, ILiquidatorGate} from "./interfaces/IGate.sol";
import {IMidnight, Market, Offer, CollateralParams, MarketState, Position} from "./interfaces/IMidnight.sol";

/// MARKETS
/// @dev The maximum time to maturity is 100 years.
/// @dev Markets have at most 128 collaterals.
/// @dev Collaterals list must be sorted by collateral address (ascending, no duplicates), and not empty.
/// @dev Within a market, a borrower can use at most MAX_COLLATERALS_PER_BORROWER (10) collaterals simultaneously.
/// @dev The case LLTV = 1 is special, and should be used with care, notably:
/// - It has no overcollateralization, so unhealthy positions will almost always realize bad debt when liquidated. In
/// particular, the RCF (see LIQUIDATIONS section) is "inactive", meaning liquidations can always liquidate everything.
/// - It has no liquidation incentive, so liquidators repay at exactly the oracle price (plus roundings).
/// @dev To check if a market has been touched, check if tickSpacing(marketId) > 0.
/// @dev When some assets become withdrawable before maturity (after a repayment or a liquidation), there
/// is an incentive to take resting sell offers with price < 1 and withdraw instantly. Lenders (and the fee claimer)
/// might also race to withdraw first.
///
/// MULTI-COLLATERAL MARKETS
/// @dev Borrowers can supply/withdraw their collaterals at any time, subject only to a health check on withdrawal. In
/// particular, the borrowers of multi-collateral markets can completely change their collateral composition.
/// @dev Liquidation reverts if any of the activated collaterals' oracle reverts (see LIVENESS).
/// @dev Note that a borrower can activate a collateral once its oracle is reverting because the oracle is not called in
/// supplyCollateral.
/// @dev The oracle-quoted liquidator incentive (i.e., maxRepayable * (LIF-1)) might not be constant across activated
/// collaterals. Hence, liquidators may have a preference order over collaterals when liquidating.
///
/// TRADING FEES
/// @dev A default trading fee (per loan token) is set on new markets. Then, the fee setter can override it.
/// @dev The trading fee is a piecewise linear function on the TTM (time to maturity). It is computed with linear
/// approximation between breakpoints.
/// @dev Trading fee breakpoint indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d, 6=360d.
/// @dev For TTM > 360d, the trading fee is the fee at the 360d breakpoint.
/// @dev Post-maturity, the trading fee is the fee at the 0d breakpoint.
/// @dev Trading fees are stored in cbp (centi-basis-points): tradingFee / CBP.
/// @dev One cbp is 1e-6 WAD, i.e. 0.01 bps. This fits each breakpoint in 16 bits.
/// @dev Max trading fee is defined per index: 50 bps for ttm=360 days, scaled linearly (except for 0d, 0.14 bps).
///
/// CONTINUOUS FEES
/// @dev A default continuous fee (per loan token) is set on new markets. Then, the fee setter can override it.
/// @dev The fee is tracked per lender via pendingFee in each position. If the market's continuous fee changes, the
/// pending fee of existing lenders is not updated (=> their fee is fixed).
/// @dev In the absence of bad debt realizations, the face value of a lender's position is credit - pendingFee.
///
/// LIQUIDATIONS
/// @dev Accounts are liquidatable only if they are either unhealthy or the maturity has passed. The liquidation
/// shouldn't be locked either.
/// @dev Liquidations are locked for the seller during the callbacks of take.
/// @dev Liquidations can revert for other reasons, see LIVENESS.
/// @dev There are two liquidation modes: The "unhealthy path", available if the borrower is unhealthy and the
/// "post-maturity path", available after the market's maturity. For an unhealthy borrower after the maturity, the
/// liquidator can choose between both modes.
/// @dev In the "unhealthy path", the liquidation incentive factor (LIF) is maxLif and the liquidation amount is capped
/// by what is needed to put back the position into health ("recovery close factor", or "RCF").
/// @dev The RCF condition is (omitting scaling and roundings):
///   newDebt >= newMaxDebt <=> debtOf - repaidUnits >= maxDebt - repaidUnits*LIF*LLTV
///                         <=> repaidUnits <= (debtOf-maxDebt) / (1 - LIF*LLTV).
/// The maxRepaid computation is rounded up to avoid consecutive max liquidations, so the position could be slightly
/// healthy after a liquidation.
/// @dev The RCF is deactivated for small collateral amount, essentially to mitigate issues with liquidations that are
/// too small compared to the gas cost. More precisely, it is deactivated if the liquidation could leave a collateral
/// with a value that would not be enough to repay rcfThreshold units. Which means (omitting scaling and roundings):
///   minNewCollateral * liquidatedCollatPrice / LIF < rcfThreshold
///     <=> (collateral - maxRepaid * LIF / liquidatedCollatPrice) * liquidatedCollatPrice / LIF < rcfThreshold
///     <=> collateral * liquidatedCollatPrice / LIF - maxRepaid < rcfThreshold
/// @dev In the "post-maturity path", the LIF (liquidation incentive factor) grows linearly from 1 at maturity to maxLif
/// at maturity + TIME_TO_MAX_LIF, and the RCF is deactivated.
///
/// SLASHING
/// @dev When a borrower's bad debt is realized, it is socialized among lenders in this market.
/// @dev At each lender's next interaction, their credit is slashed proportionally.
///
/// GROUPS
/// @dev Groups are useful to have a global offered amount shared across multiple offers ("One cancels the other").
/// @dev To work as expected, all offers in the same group should have the same max values and loan token.
///
/// OFFER CAPS
/// @dev At most one of maxAssets or maxUnits can be nonzero per offer.
/// @dev maxAssets caps max buyer assets if offer.buy is true, and caps max seller assets otherwise.
/// @dev If maxAssets > 0, assets are capped to maxAssets, otherwise units are capped to maxUnits.
/// @dev Midnight can call the callback of offers through a no-op take, even if those offers have consumed==max.
/// @dev It is possible to give units to a fully consumed assets-based buy offer with price < 1.
///
/// TICK SPACING
/// @dev Offers can only be placed at ticks that are multiples of the market's spacing.
/// @dev Newly created markets start at the global DEFAULT_TICK_SPACING.
/// @dev The tickSpacingSetter can decrease the spacing to a divisor of the current spacing, unlocking new ticks only.
///
/// AUTHORIZATIONS
/// @dev All functions that change the position, consumed and authorization are accessible to the user and to
/// any account that has been authorized. Thus, to scope authorizations one should authorize a smart-contract with
/// scoped behavior.
/// @dev When authorizing a smart-contract, one should consider:
/// - The targets/functions that the account can call. At least Midnight's functions should be considered, but other
/// contracts might re-use Midnight's authorization mapping too (e.g ratifiers and authorizers). In particular,
/// authorized accounts can authorize other accounts on behalf of the user.
/// - Under which conditions the account can return CALLBACK_SUCCESS when its isRatified function is called.
/// @dev updatePosition and liquidate (for liquidatable users) also impact the position and are permissionless.
///
/// ROUNDINGS
/// @dev Because of roundings, trading and continuous fees might charge less than expected, which can become problematic
/// for chains where the gas is cheaper than 1 asset of the loan token.
/// @dev lossFactor is rounded up so lenders collectively lose a bit more on each bad debt realization.
/// @dev updatePosition rounds the credit down, so lenders lose a bit at each interaction after a bad debt realization.
/// @dev If a market loses almost all of its value to bad debt over its lifetime, then the accounting of the loss
/// may become extremely imprecise (against the user), potentially leading to a total loss. In those cases the
/// market doesn't function properly, and notably the take function reverts when the loss factor is maxed out.
///
/// GATES
/// @dev Gates are optional (address(0) = unrestricted).
/// @dev The entry gate can prevent increasing credit or debt in the market.
/// @dev In particular, it does not prevent the user from exiting the market even when the entry gate is reverting.
/// @dev The liquidator gate can prevent the user from liquidating borrowers in the market (and realizing bad debt).
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
/// whenever the seller still has debt could revert.
/// @dev If enterGate.canIncreaseCredit reverts or returns false, take reverts if the buyer's credit increases.
/// @dev If enterGate.canIncreaseDebt reverts or returns false, take reverts if the seller's debt increases.
/// @dev If liquidatorGate.canLiquidate reverts or returns false, liquidate reverts.
/// @dev If a token pulled by Midnight reverts or returns false on transferFrom, take, repay, supplyCollateral,
/// liquidate, and flashLoan repayment revert when they need to pull that token.
/// @dev If a token sent by Midnight reverts or returns false on transfer, withdraw, withdrawCollateral, fee claims,
/// liquidate, and flashLoan revert when they need to send that token.
/// @dev If a callback reverts or returns something other than CALLBACK_SUCCESS, take, repay, liquidate, and flashLoan
/// revert.
///
/// ROLES
/// @dev The role setter can set the role setter, fee setter, fee claimer, and tick spacing setter.
/// @dev The fee setter can set the default and per-market trading fee and continuous fee.
/// @dev The fee claimer can claim the trading fee and continuous fee.
/// @dev When the claimer is set, the old claimer loses the unclaimed fees.
/// @dev The tick spacing setter can decrease the tick spacing of a market.
///
/// MISC
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
/// @dev NatSpec comments are included only when they bring clarity.
/// @dev creditOf, pendingFee, and lossFactor are not up to date. Use updatePositionView to get the up-to-date values.
/// @dev The max amount of totalUnits, collateral, credit, continuousFeeCredit and debt is type(uint128).max (~1e38).
/// @dev INITIAL_CHAIN_ID is captured at construction and used in place of block.chainid when computing market ids,
/// so a hard fork that changes block.chainid does not strand existing accounting. But as a result, after a hard-fork
/// there can be some market id clashes.
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
    mapping(bytes32 id => MarketState) public marketState;
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;
    mapping(address loanToken => uint16[7]) public defaultTradingFeeCbp;
    mapping(address loanToken => uint32) public defaultContinuousFee;
    mapping(address token => uint256) public claimableTradingFee;
    address public roleSetter;
    address public feeSetter;
    address public feeClaimer;
    address public tickSpacingSetter;

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

    function setTickSpacingSetter(address newTickSpacingSetter) external {
        require(msg.sender == roleSetter, OnlyRoleSetter());
        tickSpacingSetter = newTickSpacingSetter;
        emit EventsLib.SetTickSpacingSetter(newTickSpacingSetter);
    }

    /// @dev Refines the tick spacing of a market. Can not increase (more ticks become accessible).
    function setMarketTickSpacing(bytes32 id, uint256 newTickSpacing) external {
        require(msg.sender == tickSpacingSetter, OnlyTickSpacingSetter());
        require(marketState[id].tickSpacing > 0, MarketNotCreated());
        require(newTickSpacing > 0 && marketState[id].tickSpacing % newTickSpacing == 0, InvalidTickSpacing());
        // forge-lint: disable-next-line(unsafe-typecast) as newTickSpacing <= DEFAULT_TICK_SPACING < type(uint8).max
        marketState[id].tickSpacing = uint8(newTickSpacing);
        emit EventsLib.SetMarketTickSpacing(id, newTickSpacing);
    }

    function setMarketTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        MarketState storage _marketState = marketState[id];
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(index <= 6, InvalidFeeIndex());
        require(newTradingFee <= maxTradingFee(index), TradingFeeTooHigh());
        require(newTradingFee % CBP == 0, FeeNotMultipleOfFeeCbp());
        require(_marketState.tickSpacing > 0, MarketNotCreated());
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * CBP
        uint16 newTradingFeeCbp = uint16(newTradingFee / CBP);
        if (index == 0) _marketState.tradingFeeCbp0 = newTradingFeeCbp;
        else if (index == 1) _marketState.tradingFeeCbp1 = newTradingFeeCbp;
        else if (index == 2) _marketState.tradingFeeCbp2 = newTradingFeeCbp;
        else if (index == 3) _marketState.tradingFeeCbp3 = newTradingFeeCbp;
        else if (index == 4) _marketState.tradingFeeCbp4 = newTradingFeeCbp;
        else if (index == 5) _marketState.tradingFeeCbp5 = newTradingFeeCbp;
        else if (index == 6) _marketState.tradingFeeCbp6 = newTradingFeeCbp;
        emit EventsLib.SetMarketTradingFee(id, index, newTradingFee);
    }

    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(index <= 6, InvalidFeeIndex());
        require(newTradingFee <= maxTradingFee(index), TradingFeeTooHigh());
        require(newTradingFee % CBP == 0, FeeNotMultipleOfFeeCbp());
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * CBP
        defaultTradingFeeCbp[loanToken][index] = uint16(newTradingFee / CBP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setMarketContinuousFee(bytes32 id, uint256 newContinuousFee) external {
        MarketState storage _marketState = marketState[id];
        require(msg.sender == feeSetter, OnlyFeeSetter());
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, ContinuousFeeTooHigh());
        require(_marketState.tickSpacing > 0, MarketNotCreated());
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        _marketState.continuousFee = uint32(newContinuousFee);
        emit EventsLib.SetMarketContinuousFee(id, newContinuousFee);
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

    function claimContinuousFee(Market memory market, uint256 amount, address receiver) external {
        bytes32 id = toId(market);
        MarketState storage _marketState = marketState[id];
        require(msg.sender == feeClaimer, OnlyFeeClaimer());
        require(_marketState.tickSpacing > 0, MarketNotCreated());

        _marketState.continuousFeeCredit -= UtilsLib.toUint128(amount);
        _marketState.totalUnits -= UtilsLib.toUint128(amount);
        _marketState.withdrawable -= UtilsLib.toUint128(amount);

        emit EventsLib.ClaimContinuousFee(msg.sender, id, amount, receiver);

        SafeTransferLib.safeTransfer(market.loanToken, receiver, amount);
    }

    /// ENTRY-POINTS ///

    /// @dev The taker might not get the price they expected if the trading fee was just changed. A smart-contract can
    /// be used to perform atomic price checks.
    /// @dev Taking buy offers with price < trading fee will revert.
    /// @dev In particular, if the trading fee gets increased, it might implicitly cancel offers with very low price.
    /// @dev All sellerAssets are reachable with the units input, and all buyerAssets are reachable only if buyerPrice
    /// <= WAD.
    /// @dev The seller cannot be liquidated during the callbacks of a take.
    /// @dev Returns buyerAssets and sellerAssets.
    function take(
        Offer memory offer,
        uint256 units,
        address taker,
        address receiverIfTakerIsSeller,
        address takerCallback,
        bytes memory takerCallbackData,
        bytes memory ratifierData
    ) external returns (uint256, uint256) {
        require(taker == msg.sender || isAuthorized[taker][msg.sender], TakerUnauthorized());
        bytes32 id = touchMarket(offer.market);
        MarketState storage _marketState = marketState[id];
        require(_marketState.lossFactor < type(uint128).max, MarketLossFactorMaxedOut());
        require(UtilsLib.atMostOneNonZero(offer.maxAssets, offer.maxUnits), MultipleNonZero());
        require(offer.tick % _marketState.tickSpacing == 0, TickNotAccessible());
        require(block.timestamp >= offer.start, OfferNotStarted());
        require(block.timestamp <= offer.expiry, OfferExpired());
        require(offer.maker != taker, SelfTake());
        require(isAuthorized[offer.maker][offer.ratifier], RatifierUnauthorized());
        require(IRatifier(offer.ratifier).isRatified(offer, ratifierData) == CALLBACK_SUCCESS, RatifierFail());

        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 _tradingFee = tradingFee(id, timeToMaturity);
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        uint256 buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD);
        uint256 sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD);

        uint256 newConsumed;
        if (offer.maxAssets > 0) {
            newConsumed = consumed[offer.maker][offer.group] += offer.buy ? buyerAssets : sellerAssets;
            require(newConsumed <= offer.maxAssets, ConsumedAssets());
        } else {
            newConsumed = consumed[offer.maker][offer.group] += units;
            require(newConsumed <= offer.maxUnits, ConsumedUnits());
        }

        (address buyer, address seller) = offer.buy ? (offer.maker, taker) : (taker, offer.maker);
        Position storage buyerPos = position[id][buyer];
        Position storage sellerPos = position[id][seller];

        if (hasCredit(id, buyer) || units > buyerPos.debt) _updatePosition(offer.market, id, buyer);
        if (hasCredit(id, seller)) _updatePosition(offer.market, id, seller);

        uint256 buyerCreditIncrease = UtilsLib.zeroFloorSub(units, buyerPos.debt);
        uint256 sellerCreditDecrease = UtilsLib.min(units, sellerPos.credit);
        uint256 sellerDebtIncrease = units - sellerCreditDecrease;
        uint128 buyerPendingFeeIncrease =
            UtilsLib.toUint128(buyerCreditIncrease.mulDivDown(_marketState.continuousFee * timeToMaturity, WAD));
        uint128 sellerPendingFeeDecrease = sellerPos.credit > 0
            ? UtilsLib.toUint128(sellerPos.pendingFee.mulDivUp(sellerCreditDecrease, sellerPos.credit))
            : 0;

        require(
            !offer.reduceOnly || (offer.buy ? buyerCreditIncrease == 0 : sellerDebtIncrease == 0),
            MakerCreditOrDebtIncreased()
        );

        require(
            offer.market.enterGate == address(0) || buyerCreditIncrease == 0
                || IEnterGate(offer.market.enterGate).canIncreaseCredit(buyer),
            BuyerGatedFromIncreasingCredit()
        );
        require(
            offer.market.enterGate == address(0) || sellerDebtIncrease == 0
                || IEnterGate(offer.market.enterGate).canIncreaseDebt(seller),
            SellerGatedFromIncreasingDebt()
        );

        buyerPos.debt -= UtilsLib.toUint128(units - buyerCreditIncrease);
        buyerPos.pendingFee += buyerPendingFeeIncrease;
        buyerPos.credit += UtilsLib.toUint128(buyerCreditIncrease);

        sellerPos.pendingFee -= sellerPendingFeeDecrease;
        sellerPos.credit -= UtilsLib.toUint128(sellerCreditDecrease);
        sellerPos.debt += UtilsLib.toUint128(sellerDebtIncrease);

        _marketState.totalUnits =
            UtilsLib.toUint128(_marketState.totalUnits + buyerCreditIncrease - sellerCreditDecrease);
        claimableTradingFee[offer.market.loanToken] += buyerAssets - sellerAssets;

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
                IBuyCallback(buyerCallback)
                    .onBuy(id, offer.market, buyerAssets, units, buyerPendingFeeIncrease, buyer, buyerCallbackData)
                == CALLBACK_SUCCESS,
                WrongBuyCallbackReturnValue()
            );
        }

        SafeTransferLib.safeTransferFrom(offer.market.loanToken, payer, address(this), buyerAssets - sellerAssets);
        SafeTransferLib.safeTransferFrom(offer.market.loanToken, payer, receiver, sellerAssets);

        if (sellerCallback != address(0)) {
            bytes memory sellerCallbackData = offer.buy ? takerCallbackData : offer.callbackData;
            require(
                ISellCallback(sellerCallback)
                    .onSell(
                        id,
                        offer.market,
                        sellerAssets,
                        units,
                        sellerPendingFeeDecrease,
                        seller,
                        receiver,
                        sellerCallbackData
                    ) == CALLBACK_SUCCESS,
                WrongSellCallbackReturnValue()
            );
        }
        if (!wasLocked) UtilsLib.tExchange(LIQUIDATION_LOCK_SLOT, id, seller, false);
        require(
            position[id][seller].debt == 0 || liquidationLocked(id, seller)
                || (block.timestamp <= offer.market.maturity && isHealthy(offer.market, id, seller)),
            SellerIsLiquidatable()
        );

        return (buyerAssets, sellerAssets);
    }

    function withdraw(Market memory market, uint256 units, address onBehalf, address receiver) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchMarket(market);
        MarketState storage _marketState = marketState[id];
        _updatePosition(market, id, onBehalf);

        Position storage _position = position[id][onBehalf];
        uint128 pendingFeeDecrease;
        if (_position.credit > 0) {
            pendingFeeDecrease = UtilsLib.toUint128(_position.pendingFee.mulDivUp(units, _position.credit));
            _position.pendingFee -= pendingFeeDecrease;
        }
        _position.credit -= UtilsLib.toUint128(units);
        _marketState.withdrawable -= UtilsLib.toUint128(units);
        _marketState.totalUnits -= UtilsLib.toUint128(units);

        emit EventsLib.Withdraw(msg.sender, id, units, onBehalf, receiver, pendingFeeDecrease);

        SafeTransferLib.safeTransfer(market.loanToken, receiver, units);
    }

    function repay(Market memory market, uint256 units, address onBehalf, address callback, bytes calldata data)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchMarket(market);

        position[id][onBehalf].debt -= UtilsLib.toUint128(units);
        marketState[id].withdrawable += UtilsLib.toUint128(units);

        address payer = callback != address(0) ? callback : msg.sender;
        emit EventsLib.Repay(msg.sender, id, units, onBehalf, payer);

        if (callback != address(0)) {
            require(
                IRepayCallback(callback).onRepay(id, market, units, onBehalf, data) == CALLBACK_SUCCESS,
                WrongRepayCallbackReturnValue()
            );
        }
        SafeTransferLib.safeTransferFrom(market.loanToken, payer, address(this), units);
    }

    /// @dev This function checks authorization to prevent activated collateral poisoning.
    function supplyCollateral(Market memory market, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchMarket(market);
        address collateralToken = market.collateralParams[collateralIndex].token;

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
        Market memory market,
        uint256 collateralIndex,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        bytes32 id = touchMarket(market);
        address collateralToken = market.collateralParams[collateralIndex].token;

        Position storage _position = position[id][onBehalf];
        uint256 newCollateral = _position.collateral[collateralIndex] - assets;
        _position.collateral[collateralIndex] = UtilsLib.toUint128(newCollateral);

        if (newCollateral == 0 && assets > 0) {
            _position.collateralBitmap = _position.collateralBitmap.clearBit(collateralIndex);
        }

        require(isHealthy(market, id, onBehalf), UnhealthyBorrower());

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
        Market calldata market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bool healthyPath,
        address receiver,
        address callback,
        bytes calldata data
    ) external returns (uint256, uint256) {
        bytes32 id = touchMarket(market);
        MarketState storage _marketState = marketState[id];
        Position storage _position = position[id][borrower];
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), InconsistentInput());
        require(
            market.liquidatorGate == address(0) || ILiquidatorGate(market.liquidatorGate).canLiquidate(msg.sender),
            LiquidatorGatedFromLiquidating()
        );

        uint256 maxDebt;
        uint256 liquidatedCollatPrice;
        uint256 originalDebt = _position.debt;
        uint256 badDebt = originalDebt;
        uint128 _collateralBitmap = _position.collateralBitmap;
        while (_collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(_collateralBitmap);
            CollateralParams memory _collateralParam = market.collateralParams[i];
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
                && (healthyPath ? block.timestamp > market.maturity : originalDebt > maxDebt),
            NotLiquidatable()
        );

        if (badDebt > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(badDebt);
            uint256 _totalUnits = _marketState.totalUnits;
            uint256 _lossFactor = _marketState.lossFactor;
            _marketState.lossFactor = UtilsLib.toUint128(
                type(uint128).max - (type(uint128).max - _lossFactor).mulDivDown(_totalUnits - badDebt, _totalUnits)
            );
            _marketState.totalUnits -= UtilsLib.toUint128(badDebt);
            _marketState.continuousFeeCredit = _lossFactor < type(uint128).max
                ? UtilsLib.toUint128(
                    _marketState.continuousFeeCredit
                        .mulDivDown(type(uint128).max - _marketState.lossFactor, type(uint128).max - _lossFactor)
                )
                : 0;
        }

        if (repaidUnits > 0 || seizedAssets > 0) {
            uint256 _maxLif = market.collateralParams[collateralIndex].maxLif;
            uint256 lif = healthyPath
                ? UtilsLib.min(_maxLif, WAD + (_maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF)
                : _maxLif;

            if (seizedAssets > 0) {
                repaidUnits = seizedAssets.mulDivUp(liquidatedCollatPrice, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif);
            } else {
                seizedAssets = repaidUnits.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, liquidatedCollatPrice);
            }

            if (!healthyPath) {
                uint256 lltv = market.collateralParams[collateralIndex].lltv;
                // Note that debt >= maxDebt in this branch.
                uint256 maxRepaid = lltv < WAD
                    ? (_position.debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
                    : type(uint256).max;
                require(
                    repaidUnits <= maxRepaid
                        || _position.collateral[collateralIndex].mulDivDown(liquidatedCollatPrice, ORACLE_PRICE_SCALE)
                            .mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < market.rcfThreshold,
                    RecoveryCloseFactorConditionsViolated()
                );
            }

            uint128 newCollateral = _position.collateral[collateralIndex] - UtilsLib.toUint128(seizedAssets);
            _position.collateral[collateralIndex] = newCollateral;
            if (newCollateral == 0 && seizedAssets > 0) {
                _position.collateralBitmap = _position.collateralBitmap.clearBit(collateralIndex);
            }
            _marketState.withdrawable += UtilsLib.toUint128(repaidUnits);
            _position.debt -= UtilsLib.toUint128(repaidUnits);
        }

        address payer = callback != address(0) ? callback : msg.sender;

        emit EventsLib.Liquidate(
            msg.sender,
            id,
            market.collateralParams[collateralIndex].token,
            seizedAssets,
            repaidUnits,
            borrower,
            healthyPath,
            badDebt,
            _marketState.lossFactor,
            _marketState.continuousFeeCredit,
            payer,
            receiver
        );

        SafeTransferLib.safeTransfer(market.collateralParams[collateralIndex].token, receiver, seizedAssets);

        if (callback != address(0)) {
            require(
                ILiquidateCallback(callback)
                    .onLiquidate(
                        id,
                        market,
                        collateralIndex,
                        seizedAssets,
                        repaidUnits,
                        badDebt,
                        msg.sender,
                        borrower,
                        receiver,
                        data
                    ) == CALLBACK_SUCCESS,
                WrongLiquidateCallbackReturnValue()
            );
        }

        SafeTransferLib.safeTransferFrom(market.loanToken, payer, address(this), repaidUnits);

        return (seizedAssets, repaidUnits);
    }

    /// @dev Passing type(uint256).max cancels all offers in the group (and never reverts).
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], Unauthorized());
        require(amount >= consumed[onBehalf][group], AlreadyConsumed());
        consumed[onBehalf][group] = amount;
        emit EventsLib.SetConsumed(msg.sender, onBehalf, group, amount);
    }

    /// @dev See AUTHORIZATIONS section above.
    function setIsAuthorized(address authorized, bool newIsAuthorized, address onBehalf) external {
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
            IFlashLoanCallback(callback).onFlashLoan(tokens, assets, msg.sender, data) == CALLBACK_SUCCESS,
            WrongFlashLoanCallbackReturnValue()
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeTransferLib.safeTransferFrom(tokens[i], callback, address(this), assets[i]);
        }
    }

    /// @dev Returns the market id and creates the market if it doesn't exist yet.
    function touchMarket(Market memory market) public returns (bytes32) {
        bytes32 id = toId(market);
        if (marketState[id].tickSpacing == 0) {
            require(market.maturity <= block.timestamp + 100 * 365 days, MaturityTooFar());
            require(market.collateralParams.length > 0, NoCollateralParams());
            require(market.collateralParams.length <= MAX_COLLATERALS, TooManyCollateralParams());
            address previousCollateralToken;
            for (uint256 i = 0; i < market.collateralParams.length; i++) {
                address collateralToken = market.collateralParams[i].token;
                require(collateralToken > previousCollateralToken, CollateralParamsNotSorted());
                uint256 lltv = market.collateralParams[i].lltv;
                require(isLltvAllowed(lltv), LltvNotAllowed());
                require(
                    market.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_LOW)
                        || market.collateralParams[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_HIGH),
                    InvalidMaxLif()
                );
                previousCollateralToken = collateralToken;
            }

            MarketState storage _marketState = marketState[id];
            _marketState.tickSpacing = DEFAULT_TICK_SPACING;
            uint16[7] memory _defaultTradingFeeCbp = defaultTradingFeeCbp[market.loanToken];
            _marketState.tradingFeeCbp0 = _defaultTradingFeeCbp[0];
            _marketState.tradingFeeCbp1 = _defaultTradingFeeCbp[1];
            _marketState.tradingFeeCbp2 = _defaultTradingFeeCbp[2];
            _marketState.tradingFeeCbp3 = _defaultTradingFeeCbp[3];
            _marketState.tradingFeeCbp4 = _defaultTradingFeeCbp[4];
            _marketState.tradingFeeCbp5 = _defaultTradingFeeCbp[5];
            _marketState.tradingFeeCbp6 = _defaultTradingFeeCbp[6];
            _marketState.continuousFee = defaultContinuousFee[market.loanToken];
            IdLib.storeInCode(market, INITIAL_CHAIN_ID);

            emit EventsLib.MarketCreated(id, market);
        }
        return id;
    }

    /// SLASHING AND CONTINUOUS FEE ACCRUAL ///

    /// @dev Expects the id to correspond to the market's id.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function updatePositionView(Market memory market, bytes32 id, address user)
        public
        view
        returns (uint128, uint128, uint128)
    {
        Position storage _position = position[id][user];
        uint128 credit = _position.credit;
        uint128 _lastLossFactor = _position.lastLossFactor;
        uint256 postSlashCredit = _lastLossFactor < type(uint128).max
            ? credit.mulDivDown(type(uint128).max - marketState[id].lossFactor, type(uint128).max - _lastLossFactor)
            : 0;
        uint128 _pendingFee = _position.pendingFee;
        uint256 postSlashPendingFee =
            credit > 0 ? _pendingFee - _pendingFee.mulDivUp(credit - postSlashCredit, credit) : 0;
        uint256 accrualEnd = UtilsLib.min(block.timestamp, market.maturity);
        uint128 _lastAccrual = _position.lastAccrual;
        // forge-lint: disable-next-item(unsafe-typecast) as fee <= pending <= credit which are uint128 position fields
        uint128 fee = _lastAccrual < market.maturity
            ? uint128(postSlashPendingFee.mulDivDown(accrualEnd - _lastAccrual, market.maturity - _lastAccrual))
            : 0;
        // forge-lint: disable-next-item(unsafe-typecast) as credit and pending are <= uint128 position fields
        return (uint128(postSlashCredit) - fee, uint128(postSlashPendingFee) - fee, fee);
    }

    /// @dev Slashes the position and accrues the continuous fee.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function updatePosition(Market memory market, address user) external returns (uint128, uint128, uint128) {
        bytes32 id = toId(market);
        require(marketState[id].tickSpacing > 0, MarketNotCreated());
        return _updatePosition(market, id, user);
    }

    /// @dev Expects the market to be touched.
    /// @dev Expects the id to correspond to the market's id.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    function _updatePosition(Market memory market, bytes32 id, address user)
        internal
        returns (uint128, uint128, uint128)
    {
        Position storage _position = position[id][user];
        (uint128 newCredit, uint128 newPendingFee, uint128 accruedFee) = updatePositionView(market, id, user);

        uint128 creditDecrease = _position.credit - newCredit;
        uint128 pendingFeeDecrease = _position.pendingFee - newPendingFee;

        _position.credit = newCredit;
        _position.lastLossFactor = marketState[id].lossFactor;
        _position.pendingFee = newPendingFee;
        _position.lastAccrual = uint128(block.timestamp);
        marketState[id].continuousFeeCredit += UtilsLib.toUint128(accruedFee);

        emit EventsLib.UpdatePosition(id, user, creditDecrease, pendingFeeDecrease, accruedFee);

        return (newCredit, newPendingFee, accruedFee);
    }

    function hasCredit(bytes32 id, address user) internal view returns (bool) {
        return position[id][user].credit > 0;
    }

    /// OTHER VIEW FUNCTIONS ///

    function lastLossFactor(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lastLossFactor;
    }

    function collateralBitmap(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].collateralBitmap;
    }

    function collateral(bytes32 id, address user, uint256 index) external view returns (uint128) {
        return position[id][user].collateral[index];
    }

    function toId(Market memory market) public view returns (bytes32) {
        return IdLib.toId(market, INITIAL_CHAIN_ID, address(this));
    }

    /// @dev Reverts if the id is not a valid id of a touched market.
    /// @dev Returns the market corresponding to the given id.
    function toMarket(bytes32 id) external view returns (Market memory) {
        require(marketState[id].tickSpacing > 0, MarketNotCreated());
        address create2Address = address(uint160(uint256(id)));
        return abi.decode(create2Address.code, (Market));
    }

    function creditOf(bytes32 id, address user) external view returns (uint256) {
        return position[id][user].credit;
    }

    function debtOf(bytes32 id, address user) external view returns (uint256) {
        return position[id][user].debt;
    }

    function totalUnits(bytes32 id) external view returns (uint256) {
        return marketState[id].totalUnits;
    }

    function lossFactor(bytes32 id) external view returns (uint128) {
        return marketState[id].lossFactor;
    }

    function tickSpacing(bytes32 id) external view returns (uint8) {
        return marketState[id].tickSpacing;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return marketState[id].withdrawable;
    }

    /// @dev The trading fee cbp values are 0 until the market is created, then set to the default value.
    function tradingFeeCbps(bytes32 id) external view returns (uint16[7] memory) {
        return [
            marketState[id].tradingFeeCbp0,
            marketState[id].tradingFeeCbp1,
            marketState[id].tradingFeeCbp2,
            marketState[id].tradingFeeCbp3,
            marketState[id].tradingFeeCbp4,
            marketState[id].tradingFeeCbp5,
            marketState[id].tradingFeeCbp6
        ];
    }

    /// @dev The continuous fee is 0 until the market is created, then set to the default value.
    function continuousFee(bytes32 id) external view returns (uint32) {
        return marketState[id].continuousFee;
    }

    function continuousFeeCredit(bytes32 id) external view returns (uint256) {
        return marketState[id].continuousFeeCredit;
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

    /// @dev This function should be called with the id corresponding to the market.
    /// @dev This function does not call any oracle if debt is 0.
    /// @dev Expects the id to correspond to the market's id.
    function isHealthy(Market memory market, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        if (debt > 0) {
            uint128 _collateralBitmap = _position.collateralBitmap;
            while (_collateralBitmap != 0) {
                uint256 i = UtilsLib.msb(_collateralBitmap);
                CollateralParams memory collateralParam = market.collateralParams[i];
                uint256 price = IOracle(collateralParam.oracle).price();
                maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE)
                    .mulDivDown(collateralParam.lltv, WAD);
                _collateralBitmap = _collateralBitmap.clearBit(i);
            }
        }
        return maxDebt >= debt;
    }

    /// @dev Returns the trading fee using piecewise linear interpolation between breakpoints.
    function tradingFee(bytes32 id, uint256 timeToMaturity) public view returns (uint256) {
        MarketState storage _marketState = marketState[id];
        require(_marketState.tickSpacing > 0, MarketNotCreated());

        if (timeToMaturity >= 360 days) return _marketState.tradingFeeCbp6 * CBP;

        // forgefmt: disable-start
        (uint256 start, uint256 end, uint256 feeLower, uint256 feeUpper) =
            timeToMaturity < 1 days   ? (  0 days,   1 days, _marketState.tradingFeeCbp0 * CBP, _marketState.tradingFeeCbp1 * CBP) :
            timeToMaturity < 7 days   ? (  1 days,   7 days, _marketState.tradingFeeCbp1 * CBP, _marketState.tradingFeeCbp2 * CBP) :
            timeToMaturity < 30 days  ? (  7 days,  30 days, _marketState.tradingFeeCbp2 * CBP, _marketState.tradingFeeCbp3 * CBP) :
            timeToMaturity < 90 days  ? ( 30 days,  90 days, _marketState.tradingFeeCbp3 * CBP, _marketState.tradingFeeCbp4 * CBP) :
            timeToMaturity < 180 days ? ( 90 days, 180 days, _marketState.tradingFeeCbp4 * CBP, _marketState.tradingFeeCbp5 * CBP) :
                                        (180 days, 360 days, _marketState.tradingFeeCbp5 * CBP, _marketState.tradingFeeCbp6 * CBP);
        // forgefmt: disable-end

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
