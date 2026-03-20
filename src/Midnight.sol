// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {IdLib} from "./libraries/IdLib.sol";
import {TickLib} from "./libraries/TickLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {
    WAD,
    ORACLE_PRICE_SCALE,
    FEE_STEP,
    MAX_CONTINUOUS_FEE,
    TIME_TO_MAX_LIF,
    MAX_COLLATERALS,
    MAX_COLLATERALS_PER_BORROWER,
    LIQUIDATION_CURSOR_LOW,
    LIQUIDATION_CURSOR_HIGH,
    EIP712_DOMAIN_TYPEHASH,
    ROOT_TYPEHASH,
    PASSIVE_FEE_RECIPIENT
} from "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {
    IMidnight,
    Obligation,
    Offer,
    Signature,
    Collateral,
    ObligationState,
    Position
} from "./interfaces/IMidnight.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// MAX AMOUNTS
/// @dev The max amount of totalUnits, collateral, credit, and debt is type(uint128).max (~1e38).
///
/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
///
/// TRADING FEES
/// @dev The trading fee is computed using piecewise linear interpolation between breakpoints.
/// @dev Trading fee breakpoint indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d, 6=360d.
/// @dev For TTM > 360d, the trading fee is the fee at the 360d breakpoint.
/// @dev Post-maturity, the trading fee is the fee at the 0d breakpoint.
/// @dev Trading fees are stored divided by FEE_STEP (1e12) to fit in 16 bits.
/// @dev Max trading fee is defined per index (see maxTradingFee function).
///
/// ROUNDINGS
/// @dev lossIndex is rounded up so lenders collectively lose a bit more on each bad debt realization.
/// @dev slash rounds the credit down, so lenders lose a bit at each interaction.
/// @dev If an obligation loses more than 99%+ of its value to bad debt over its lifetime, it won't function properly
/// afterwards (bad debt can no longer be realized).
contract Midnight is IMidnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;
    using UtilsLib for uint64;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => Position)) internal position;
    mapping(bytes32 id => ObligationState) public obligationState;

    /// @dev Groups are useful to have a global offered amount shared across multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same units and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

    /// @dev Whether an address is authorized to act on behalf of another address.
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;

    /// @dev Default trading fees per loan token. Set when the obligation is created. Can be later overriden by the
    /// feeSetter.
    mapping(address loanToken => uint16[7]) public defaultTradingFees;

    /// @dev Default continuous fee per loan token. Set when the obligation is created. Can be later overriden by the
    /// feeSetter.
    mapping(address loanToken => uint32) public defaultContinuousFee;

    address public feeRecipient;

    /// @dev Contract owner for administrative functions.
    address public owner;

    /// @dev Address that can set trading fees.
    address public feeSetter;

    /// CONSTRUCTOR ///

    constructor() {
        owner = msg.sender;
        emit EventsLib.Constructor(owner);
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

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "only owner");
        owner = newOwner;
        emit EventsLib.SetOwner(newOwner);
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == owner, "only owner");
        feeSetter = newFeeSetter;
        emit EventsLib.SetFeeSetter(newFeeSetter);
    }

    /// @dev Overrides the fee of a specific obligation.
    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "value too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        require(obligationState[id].created, "obligation not created");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        obligationState[id].fees[index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    /// @dev Doesn't change the fee of already created obligations.
    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "value too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee <= maxTradingFee <= uint16.max * FEE_STEP
        defaultTradingFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setFeeRecipient(address newFeeRecipient) external {
        require(msg.sender == owner, "only owner");
        feeRecipient = newFeeRecipient;
        emit EventsLib.SetFeeRecipient(newFeeRecipient);
    }

    function setObligationContinuousFee(bytes32 id, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, "continuous fee too high");
        require(obligationState[id].created, "obligation not created");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        obligationState[id].continuousFee = uint32(newContinuousFee);
        emit EventsLib.SetObligationContinuousFee(id, newContinuousFee);
    }

    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(newContinuousFee <= MAX_CONTINUOUS_FEE, "continuous fee too high");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= MAX_CONTINUOUS_FEE < type(uint32).max
        defaultContinuousFee[loanToken] = uint32(newContinuousFee);
        emit EventsLib.SetDefaultContinuousFee(loanToken, newContinuousFee);
    }

    /// ENTRY-POINTS ///

    /// @dev Returns buyerAssets, sellerAssets, units.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev The taker might not get the price they expected if the trading fee was just changed.
    /// @dev All sellerAssets are reachable with the units input, and all buyerAssets are reachable only if
    /// buyerPrice <= WAD.
    function take(
        uint256 units,
        address taker,
        address takerCallback,
        bytes memory takerCallbackData,
        address receiverIfTakerIsSeller,
        Offer memory offer,
        Signature memory sig,
        bytes32 root,
        bytes32[] memory proof
    ) external returns (uint256, uint256, uint256) {
        require(taker == msg.sender || isAuthorized[taker][msg.sender], "unauthorized");
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(offer.maker != taker, "buyer and seller cannot be the same");
        require(signer(root, sig) == offer.maker, "invalid signature");
        require(UtilsLib.isLeaf(root, keccak256(abi.encode(offer)), proof), "invalid proof");
        require(offer.session == session[offer.maker], "invalid session");
        bytes32 id = touchObligation(offer.obligation);
        slashAndAccrue(offer.obligation, id, offer.maker);
        slashAndAccrue(offer.obligation, id, taker);
        ObligationState storage _obligationState = obligationState[id];

        (
            address buyer,
            address buyerCallback,
            bytes memory buyerCallbackData,
            address seller,
            address sellerCallback,
            bytes memory sellerCallbackData,
            address receiver
        ) = offer.buy
            ? (
                offer.maker,
                offer.callback,
                offer.callbackData,
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller
            )
            : (
                taker,
                takerCallback,
                takerCallbackData,
                offer.maker,
                offer.callback,
                offer.callbackData,
                offer.receiverIfMakerIsSeller
            );

        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        uint256 _tradingFee = tradingFee(id, timeToMaturity);
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        uint256 buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD);
        uint256 sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD);

        uint256 newConsumed = consumed[offer.maker][offer.group] += units;
        require(newConsumed <= offer.maxUnits, "consumed");

        Position storage buyerPos = position[id][buyer];
        Position storage sellerPos = position[id][seller];
        uint256 buyerCreditIncrease = UtilsLib.zeroFloorSub(units, buyerPos.debt);
        uint256 sellerCreditDecrease = UtilsLib.min(units, sellerPos.credit);
        buyerPos.debt -= UtilsLib.toUint128(units - buyerCreditIncrease);
        buyerPos.pendingFee += UtilsLib.toUint128(
            buyerCreditIncrease.mulDivDown(_obligationState.continuousFee * timeToMaturity, WAD)
        );
        buyerPos.credit += UtilsLib.toUint128(buyerCreditIncrease);
        if (sellerPos.credit > 0) {
            sellerPos.pendingFee -= UtilsLib.toUint128(
                uint256(sellerPos.pendingFee).mulDivUp(sellerCreditDecrease, sellerPos.credit)
            );
        }
        sellerPos.credit -= UtilsLib.toUint128(sellerCreditDecrease);
        sellerPos.debt += UtilsLib.toUint128(units - sellerCreditDecrease);
        _obligationState.totalUnits =
            UtilsLib.toUint128(_obligationState.totalUnits + buyerCreditIncrease - sellerCreditDecrease);

        require(buyerPos.pendingFee <= buyerPos.credit, "buyer pendingFee exceeds credit");
        if (offer.exitOnly) require(offer.buy ? buyerPos.credit == 0 : sellerPos.debt == 0, "crossed");

        emit EventsLib.Take(
            msg.sender,
            id,
            offer.maker,
            taker,
            offer.buy,
            buyerAssets,
            sellerAssets,
            units,
            receiver,
            offer.group,
            newConsumed,
            _obligationState.totalUnits,
            buyerPos.pendingFee,
            sellerPos.pendingFee
        );

        if (buyerCallback != address(0)) {
            ICallbacks(buyerCallback)
                .onBuy(offer.obligation, buyer, buyerAssets, sellerAssets, units, buyerCallbackData);
        }

        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, feeRecipient, buyerAssets - sellerAssets);
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, receiver, sellerAssets);

        if (sellerCallback != address(0)) {
            ICallbacks(sellerCallback)
                .onSell(offer.obligation, seller, buyerAssets, sellerAssets, units, sellerCallbackData);
        }

        require(isHealthy(offer.obligation, id, seller), "seller is unhealthy");

        return (buyerAssets, sellerAssets, units);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 units, address onBehalf, address receiver) external {
        require(
            onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender]
                || (onBehalf == PASSIVE_FEE_RECIPIENT && msg.sender == feeRecipient),
            "unauthorized"
        );
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
        slashAndAccrue(obligation, id, onBehalf);

        Position storage _position = position[id][onBehalf];
        if (_position.credit > 0) {
            _position.pendingFee -= UtilsLib.toUint128(_position.pendingFee.mulDivUp(units, _position.credit));
        }
        _position.credit -= UtilsLib.toUint128(units);
        _obligationState.withdrawable -= units;
        _obligationState.totalUnits -= UtilsLib.toUint128(units);

        emit EventsLib.Withdraw(msg.sender, id, units, onBehalf, receiver);

        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, units);
    }

    function repay(Obligation memory obligation, uint256 units, address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);

        Position storage _position = position[id][onBehalf];
        _position.debt -= UtilsLib.toUint128(units);
        obligationState[id].withdrawable += units;

        emit EventsLib.Repay(msg.sender, id, units, onBehalf, _position.pendingFee);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), units);
    }

    /// @dev This function checks authorization to prevent activated collateral poisoning.
    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collaterals[collateralIndex].token;

        Position storage _position = position[id][onBehalf];
        uint256 oldCollateralOf = _position.collateral[collateralIndex];
        _position.collateral[collateralIndex] = UtilsLib.toUint128(oldCollateralOf + assets);

        if (oldCollateralOf == 0 && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            uint128 newBitmap = _position.activatedCollaterals | uint128(1 << collateralIndex);
            _position.activatedCollaterals = newBitmap;
            require(UtilsLib.countBits(newBitmap) <= MAX_COLLATERALS_PER_BORROWER, "too many collaterals per borrower");
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
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collaterals[collateralIndex].token;

        Position storage _position = position[id][onBehalf];
        uint256 newCollateralOf = _position.collateral[collateralIndex] - assets;
        _position.collateral[collateralIndex] = UtilsLib.toUint128(newCollateralOf);

        if (newCollateralOf == 0 && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            _position.activatedCollaterals &= ~uint128(1 << collateralIndex);
        }

        require(isHealthy(obligation, id, onBehalf), "unhealthy borrower");

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateralToken, assets, onBehalf, receiver);

        SafeTransferLib.safeTransfer(collateralToken, receiver, assets);
    }

    /// @dev At least one of `seizedAssets` or `repaidUnits` should be equal to zero.
    /// @dev Accounts are liquidatable if they are unhealthy or if the maturity has passed.
    /// @dev Before maturity, the liquidation cannot put the borrower back into health (recovery close factor), unless
    /// the liquidation could leave a collateral with a value that would not be enough to repay rcfThreshold units.
    /// @dev Recovery close factor means that debtOf - repaidUnits >= maxDebt - repaidUnits*LIF*LLTV, which is
    /// equivalent to repaidUnits <= (debtOf-maxDebt) / (1 - LIF*LLTV).
    /// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to maxLif(lltv) at maturity +
    /// TIME_TO_MAX_LIF.
    /// @dev Liquidating non zero amounts reverts if LLTV = 1.
    /// @dev Returns the seized assets and the repaid units.
    function liquidate(
        Obligation calldata obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes calldata data
    ) external returns (uint256, uint256) {
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), "inconsistent input");
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
        Position storage _position = position[id][borrower];

        uint256 maxDebt;
        uint256 liquidatedCollatPrice;
        uint256 originalDebt = _position.debt;
        uint256 badDebt = originalDebt;
        uint256 bitmap = _position.activatedCollaterals;
        while (bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            if (i == collateralIndex) liquidatedCollatPrice = price;
            uint256 _collateralOf = _position.collateral[i];
            maxDebt += _collateralOf.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateral.lltv, WAD);
            badDebt = badDebt.zeroFloorSub(
                _collateralOf.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateral.maxLif)
            );
            bitmap ^= (1 << i);
        }

        require(block.timestamp > obligation.maturity || originalDebt > maxDebt, "position is not liquidatable");

        if (badDebt > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(badDebt);
            uint256 oldTotalUnits = _obligationState.totalUnits;
            _obligationState.lossIndex = UtilsLib.toUint128(
                type(uint128).max
                    - (type(uint128).max - _obligationState.lossIndex)
                    .mulDivDown(oldTotalUnits - badDebt, oldTotalUnits)
            );
            _obligationState.totalUnits -= UtilsLib.toUint128(badDebt);
        }

        if (repaidUnits > 0 || seizedAssets > 0) {
            uint256 _maxLif = obligation.collaterals[collateralIndex].maxLif;
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
                uint256 lltv = obligation.collaterals[collateralIndex].lltv;
                // Rounded up to avoid consecutive max liquidations.
                // Acknowledged that the position could be slightly healthy after a liquidation.
                // Note that debt >= maxDebt in this branch.
                uint256 maxRepaid = (_position.debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD));
                require(
                    repaidUnits <= maxRepaid
                        || _position.collateral[collateralIndex].mulDivDown(liquidatedCollatPrice, ORACLE_PRICE_SCALE)
                            .mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < obligation.rcfThreshold,
                    "recovery close factor conditions violated"
                );
            }

            uint128 newCollateralOf = _position.collateral[collateralIndex] - UtilsLib.toUint128(seizedAssets);
            _position.collateral[collateralIndex] = newCollateralOf;
            if (newCollateralOf == 0 && seizedAssets > 0) {
                // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
                _position.activatedCollaterals &= ~uint128(1 << collateralIndex);
            }
            _obligationState.withdrawable += repaidUnits;
            _position.debt -= UtilsLib.toUint128(repaidUnits);
        }

        emit EventsLib.Liquidate(
            msg.sender,
            id,
            collateralIndex,
            seizedAssets,
            repaidUnits,
            borrower,
            badDebt,
            _obligationState.lossIndex,
            _position.pendingFee
        );

        SafeTransferLib.safeTransfer(obligation.collaterals[collateralIndex].token, msg.sender, seizedAssets);

        if (data.length > 0) {
            ICallbacks(msg.sender).onLiquidate(obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), repaidUnits);

        return (seizedAssets, repaidUnits);
    }

    /// @dev Passing type(uint256).max cancels all offers in the group (and never reverts).
    function setConsumed(bytes32 group, uint256 amount, address onBehalf) external {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        require(amount >= consumed[onBehalf][group], "consumed");

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
        bytes32 id = IdLib.toId(obligation, block.chainid, address(this));
        if (!obligationState[id].created) {
            require(obligation.collaterals.length > 0, "no collaterals");
            require(obligation.collaterals.length <= MAX_COLLATERALS, "too many collaterals");
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                address collateralToken = obligation.collaterals[i].token;
                require(collateralToken > previousCollateralToken, "collaterals not sorted");
                uint256 lltv = obligation.collaterals[i].lltv;
                require(lltv <= WAD, "lltv too high");
                require(
                    obligation.collaterals[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_LOW)
                        || obligation.collaterals[i].maxLif == maxLif(lltv, LIQUIDATION_CURSOR_HIGH),
                    "invalid maxLif"
                );
                previousCollateralToken = collateralToken;
            }

            obligationState[id].created = true;
            obligationState[id].fees = defaultTradingFees[obligation.loanToken];
            obligationState[id].continuousFee = defaultContinuousFee[obligation.loanToken];
            IdLib.storeInCode(obligation);

            emit EventsLib.ObligationCreated(id, obligation);
        }
        return id;
    }

    function slashAndAccrue(Obligation memory obligation, address user) external {
        bytes32 id = IdLib.toId(obligation, block.chainid, address(this));
        require(obligationState[id].created, "not created");
        slashAndAccrue(obligation, id, user);
    }

    function slashAndAccrue(Obligation memory obligation, bytes32 id, address user) internal {
        Position storage _position = position[id][user];
        uint128 lossIndex = obligationState[id].lossIndex;
        if (_position.lossIndex != lossIndex) {
            uint256 creditBefore = _position.credit;
            uint256 newCredit = slashView(id, user);
            if (creditBefore > 0) {
                _position.pendingFee -= UtilsLib.toUint128(
                    _position.pendingFee.mulDivUp(creditBefore - newCredit, creditBefore)
                );
            }
            // forge-lint: disable-next-item(unsafe-typecast) as newCredit <= creditBefore
            _position.credit = uint128(newCredit);
            _position.lossIndex = lossIndex;
            emit EventsLib.Slash(msg.sender, id, user, newCredit, lossIndex);
        }

        // forge-lint: disable-next-item(unsafe-typecast) as accrued fee is <= pendingFee
        uint128 accruedFee = uint128(accrueView(id, user, obligation.maturity));
        if (accruedFee > 0) {
            _position.pendingFee -= accruedFee;
            _position.credit -= accruedFee;
            slashAndAccrue(obligation, id, PASSIVE_FEE_RECIPIENT);
            position[id][PASSIVE_FEE_RECIPIENT].credit += accruedFee;
        }
        _position.lastContinuousFeeAccrual = uint128(block.timestamp);

        emit EventsLib.AccrueContinuousFee(id, user, accruedFee, _position.pendingFee);
    }

    /// VIEW FUNCTIONS ///

    function userLossIndex(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lossIndex;
    }

    function activatedCollaterals(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].activatedCollaterals;
    }

    function collateralOf(bytes32 id, address user, uint256 index) external view returns (uint128) {
        return position[id][user].collateral[index];
    }

    function toId(Obligation memory obligation) external view returns (bytes32) {
        return IdLib.toId(obligation, block.chainid, address(this));
    }

    /// @dev Returns the obligation corresponding to the given id.
    /// @dev Reverts if the id is not a valid id of a touched obligation.
    function toObligation(bytes32 id) external view returns (Obligation memory) {
        require(obligationState[id].created, "not created");
        address create2Address = address(uint160(uint256(id)));
        return abi.decode(create2Address.code, (Obligation));
    }

    function creditOf(bytes32 id, address user) external view returns (uint256) {
        return uint256(position[id][user].credit);
    }

    function debtOf(bytes32 id, address user) external view returns (uint256) {
        return uint256(position[id][user].debt);
    }

    function totalUnits(bytes32 id) external view returns (uint256) {
        return obligationState[id].totalUnits;
    }

    function obligationCreated(bytes32 id) external view returns (bool) {
        return obligationState[id].created;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return obligationState[id].withdrawable;
    }

    function fees(bytes32 id) external view returns (uint16[7] memory) {
        return obligationState[id].fees;
    }

    function continuousFee(bytes32 id) external view returns (uint32) {
        return obligationState[id].continuousFee;
    }

    function pendingFee(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].pendingFee;
    }

    function lastContinuousFeeAccrual(bytes32 id, address user) external view returns (uint128) {
        return position[id][user].lastContinuousFeeAccrual;
    }

    /// @dev This function should be called with the id corresponding to the obligation.
    /// @dev This function does not call any oracle if debt is 0.
    /// @dev Expects the id to correspond to the obligation's id.
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        uint256 bitmap = _position.activatedCollaterals;
        while (maxDebt < debt && bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(collateral.lltv, WAD);
            bitmap ^= (1 << i);
        }
        return maxDebt >= debt;
    }

    function domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function signer(bytes32 root, Signature memory signature) internal view returns (address) {
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator(), structHash));
        address tentativeSigner = ecrecover(digest, signature.v, signature.r, signature.s);
        require(tentativeSigner != address(0), "invalid signature");
        return tentativeSigner;
    }

    /// @dev Returns the accrued fee after simulating slash.
    function slashAndAccrueView(Obligation memory obligation, address user) public view returns (uint256) {
        bytes32 id = IdLib.toId(obligation, block.chainid, address(this));
        Position storage _position = position[id][user];
        uint256 creditBefore = _position.credit;
        if (creditBefore > 0) {
            uint256 creditAfter = slashView(id, user);
            if (creditAfter < creditBefore) {
                uint256 fee = accrueView(id, user, obligation.maturity);
                return fee - fee.mulDivUp(creditBefore - creditAfter, creditBefore);
            }
        }
        return accrueView(id, user, obligation.maturity);
    }

    function slashView(bytes32 id, address user) internal view returns (uint256) {
        Position storage _position = position[id][user];
        uint128 _userLossIndex = _position.lossIndex;
        uint128 lossIndex = obligationState[id].lossIndex;
        if (_userLossIndex == lossIndex) {
            return _position.credit;
        } else {
            return _position.credit.mulDivDown(type(uint128).max - lossIndex, type(uint128).max - _userLossIndex);
        }
    }

    function accrueView(bytes32 id, address user, uint256 maturity) internal view returns (uint256) {
        Position storage _position = position[id][user];
        uint256 lastAccrual = _position.lastContinuousFeeAccrual;
        if (lastAccrual == 0 || lastAccrual >= maturity) {
            return 0;
        } else {
            uint256 accrualEnd = UtilsLib.min(block.timestamp, maturity);
            return _position.pendingFee.mulDivDown(accrualEnd - lastAccrual, maturity - lastAccrual);
        }
    }

    function maxLif(uint256 lltv, uint256 cursor) public pure returns (uint256) {
        return WAD.mulDivDown(WAD, WAD - cursor.mulDivDown(WAD - lltv, WAD));
    }

    /// @dev 50 bps for ttm=360 days, scaled linearly. For post maturity, 0.14 bps.
    function maxTradingFee(uint256 index) public pure returns (uint256) {
        return [0.000014e18, 0.000014e18, 0.000098e18, 0.000417e18, 0.00125e18, 0.0025e18, 0.005e18][index];
    }

    /// @dev Returns the trading fee using piecewise linear interpolation between breakpoints.
    function tradingFee(bytes32 id, uint256 timeToMaturity) public view returns (uint256) {
        require(obligationState[id].created, "not created");

        uint16[7] memory _fees = obligationState[id].fees;

        if (timeToMaturity >= 360 days) return _fees[6] * FEE_STEP;

        // forgefmt: disable-start
        (uint256 index, uint256 start, uint256 end) =
            timeToMaturity < 1 days   ? (0, 0 days, 1 days) :
            timeToMaturity < 7 days   ? (1, 1 days, 7 days) :
            timeToMaturity < 30 days  ? (2, 7 days, 30 days) :
            timeToMaturity < 90 days  ? (3, 30 days, 90 days) :
            timeToMaturity < 180 days ? (4, 90 days, 180 days) :
                                        (5, 180 days, 360 days);
        // forgefmt: disable-end

        uint256 feeLower = _fees[index] * FEE_STEP;
        uint256 feeUpper = _fees[index + 1] * FEE_STEP;

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
