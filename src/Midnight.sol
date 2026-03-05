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
    TIME_TO_MAX_LIF,
    MAX_COLLATERALS,
    MAX_COLLATERALS_PER_BORROWER,
    LIQUIDATION_CURSOR_LOW,
    LIQUIDATION_CURSOR_HIGH,
    EIP712_DOMAIN_TYPEHASH,
    ROOT_TYPEHASH
} from "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMidnight, Obligation, Offer, Signature, Collateral, ObligationState} from "./interfaces/IMidnight.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// MAX AMOUNTS
/// @dev The max amount of debt, totalUnits, totalShares, and collateral is type(uint128).max (~1e38).
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
contract Midnight is IMidnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => int256)) public balanceOf;
    mapping(bytes32 id => mapping(address user => uint256)) public userLossIndex;
    mapping(bytes32 id => mapping(address user => uint128)) public activatedCollaterals;
    mapping(bytes32 id => mapping(address user => uint128[128])) public collateralOf;
    mapping(bytes32 id => ObligationState) public obligationState;

    /// @dev Groups are useful to have a global offered amount shared across multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same obligationUnits and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

    /// @dev Whether an address is authorized to manage positions on behalf of another address.
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;

    /// @dev Default fees per loan token. Set when the obligation is created. Can be later changed (in both directions)
    /// by the feeSetter.
    mapping(address loanToken => uint16[7]) public defaultFees;

    /// @dev Default continuous fee per loan token. Set when the obligation is created. Can be later decreased by the
    /// feeSetter.
    mapping(address loanToken => uint64) public defaultContinuousFees;

    /// @dev Trading fee recipient.
    address public tradingFeeRecipient;

    /// @dev Continuous fee recipient.
    address public continuousFeeRecipient;

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

    /// OWNER FUNCTIONS ///

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

    function setTradingFeeRecipient(address recipient) external {
        require(msg.sender == owner, "only owner");
        tradingFeeRecipient = recipient;
        emit EventsLib.SetTradingFeeRecipient(recipient);
    }

    function setContinuousFeeRecipient(address recipient) external {
        require(msg.sender == owner, "only owner");
        continuousFeeRecipient = recipient;
        emit EventsLib.SetContinuousFeeRecipient(recipient);
    }

    /// FEE SETTER FUNCTIONS ///

    /// @dev Overrides the fee of a specific obligation.
    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "value too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        require(obligationState[id].created, "obligation not created");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee is less than maxTradingFee
        obligationState[id].fees[index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    /// @dev Doesn't change the fee of already created obligations.
    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "only fee setter");
        require(index <= 6, "invalid index");
        require(newTradingFee <= maxTradingFee(index), "value too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee is less than maxTradingFee
        defaultFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    /// @dev Overrides the continuous fee of a specific obligation. Can only decrease the fee.
    function setObligationContinuousFee(bytes32 id, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newContinuousFee <= obligationState[id].continuousFee, "Continuous fee can only decrease");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= 317097919 < type(uint64).max
        obligationState[id].continuousFee = uint64(newContinuousFee);
        emit EventsLib.SetObligationContinuousFee(id, newContinuousFee);
    }

    /// @dev Doesn't change the fee of already created obligations.
    function setDefaultContinuousFee(address loanToken, uint256 newContinuousFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newContinuousFee <= uint256(0.01e18) / uint256(365 days), "Continuous fee too high");
        // forge-lint: disable-next-line(unsafe-typecast) as newContinuousFee <= 317097919 < type(uint64).max
        defaultContinuousFees[loanToken] = uint64(newContinuousFee);
        emit EventsLib.SetDefaultContinuousFee(loanToken, newContinuousFee);
    }

    /// ENTRY-POINTS ///

    /// @dev Returns buyerAssets, sellerAssets, obligationUnits.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev The taker might not get the price they expected if the trading fee was just changed.
    /// @dev All sellerAssets are reachable with the obligationShares input, and all buyerAssets are reachable only if
    /// buyerPrice <= WAD.
    function take(
        uint256 obligationUnits,
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
        accrueFees(id);
        slash(id, offer.maker);
        slash(id, taker);
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
        uint256 buyerAssets =
            offer.buy ? obligationUnits.mulDivDown(buyerPrice, WAD) : obligationUnits.mulDivUp(buyerPrice, WAD);
        uint256 sellerAssets =
            offer.buy ? obligationUnits.mulDivDown(sellerPrice, WAD) : obligationUnits.mulDivUp(sellerPrice, WAD);

        uint256 newConsumed = consumed[offer.maker][offer.group] += obligationUnits;
        consumed[offer.maker][offer.group] = newConsumed;
        require(newConsumed <= offer.obligationUnits, "consumed");

        int256 oldBuyerBalance = balanceOf[id][buyer];
        int256 oldSellerBalance = balanceOf[id][seller];
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 newBuyerBalance = oldBuyerBalance + int256(obligationUnits);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 newSellerBalance = oldSellerBalance - int256(obligationUnits);
        balanceOf[id][buyer] = newBuyerBalance;
        balanceOf[id][seller] = newSellerBalance;
        if (offer.asLender) require((offer.buy ? newBuyerBalance : newSellerBalance) >= 0, "crossed");
        _obligationState.totalUnits = UtilsLib.toUint128(
            uint256(_obligationState.totalUnits) + UtilsLib.negativePart(newSellerBalance)
                + UtilsLib.negativePart(newBuyerBalance) - UtilsLib.negativePart(oldSellerBalance)
                - UtilsLib.negativePart(oldBuyerBalance)
        );

        emit EventsLib.Take(
            msg.sender,
            id,
            offer.maker,
            taker,
            offer.buy,
            buyerAssets,
            sellerAssets,
            obligationUnits,
            receiver,
            offer.group,
            newConsumed
        );

        if (buyerCallback != address(0)) {
            ICallbacks(buyerCallback)
                .onBuy(offer.obligation, buyer, buyerAssets, sellerAssets, obligationUnits, buyerCallbackData);
        }

        SafeTransferLib.safeTransferFrom(
            offer.obligation.loanToken, buyer, tradingFeeRecipient, buyerAssets - sellerAssets
        );
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, receiver, sellerAssets);

        if (sellerCallback != address(0)) {
            ICallbacks(sellerCallback)
                .onSell(offer.obligation, seller, buyerAssets, sellerAssets, obligationUnits, sellerCallbackData);
        }

        require(isHealthy(offer.obligation, id, seller), "seller is unhealthy");

        return (buyerAssets, sellerAssets, obligationUnits);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, address onBehalf, address receiver)
        external
        returns (uint256)
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
        accrueFees(id);
        slash(id, onBehalf);

        // forge-lint: disable-next-line(unsafe-typecast)
        balanceOf[id][onBehalf] -= int256(obligationUnits);
        require(balanceOf[id][onBehalf] >= 0, "withdraw too much");
        _obligationState.withdrawable -= obligationUnits;
        _obligationState.totalUnits -= UtilsLib.toUint128(obligationUnits);

        emit EventsLib.Withdraw(msg.sender, id, obligationUnits, onBehalf, receiver);

        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, obligationUnits);

        return obligationUnits;
    }

    function repay(Obligation memory obligation, uint256 obligationUnits, address onBehalf) external {
        bytes32 id = touchObligation(obligation);

        // forge-lint: disable-next-line(unsafe-typecast)
        balanceOf[id][onBehalf] += int256(obligationUnits);
        require(balanceOf[id][onBehalf] <= 0, "repay too much");
        obligationState[id].withdrawable += obligationUnits;

        emit EventsLib.Repay(msg.sender, id, obligationUnits, onBehalf);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), obligationUnits);
    }

    /// @dev This function checks authorization to prevent activated collateral poisoning.
    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "unauthorized");
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collaterals[collateralIndex].token;

        uint256 oldCollateralOf = collateralOf[id][onBehalf][collateralIndex];
        collateralOf[id][onBehalf][collateralIndex] = UtilsLib.toUint128(oldCollateralOf + assets);

        if (oldCollateralOf == 0 && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            uint128 newBitmap = activatedCollaterals[id][onBehalf] | uint128(1 << collateralIndex);
            activatedCollaterals[id][onBehalf] = newBitmap;
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

        uint256 newCollateralOf = collateralOf[id][onBehalf][collateralIndex] - assets;
        collateralOf[id][onBehalf][collateralIndex] = UtilsLib.toUint128(newCollateralOf);

        if (newCollateralOf == 0 && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            activatedCollaterals[id][onBehalf] &= ~uint128(1 << collateralIndex);
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
    /// @dev Liquidations non zero amounts revert if LLTV = 1.
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

        uint256 maxDebt;
        uint256 liquidatedCollatPrice;
        uint256 originalDebt = debtOf(id, borrower);
        uint256 badDebt = originalDebt;
        uint256 bitmap = activatedCollaterals[id][borrower];
        while (bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            if (i == collateralIndex) liquidatedCollatPrice = price;
            uint256 collateralQuoted = collateralOf[id][borrower][i].mulDivDown(price, ORACLE_PRICE_SCALE);
            maxDebt += collateralQuoted.mulDivDown(_collateral.lltv, WAD);
            badDebt = badDebt.zeroFloorSub(collateralQuoted.mulDivDown(WAD, _collateral.maxLif));
            bitmap ^= (1 << i);
        }

        require(block.timestamp > obligation.maturity || originalDebt > maxDebt, "position is not liquidatable");

        if (badDebt > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            balanceOf[id][borrower] += int256(badDebt);
            uint256 oldTotalUnits = _obligationState.totalUnits;
            _obligationState.lossIndex =
                WAD - (WAD - _obligationState.lossIndex).mulDivDown(oldTotalUnits - badDebt, oldTotalUnits);
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
                // Note that debt >= Σ collateralQuoted * 1 / lif >= Σ collateralQuoted * lltv = maxDebt.
                uint256 maxRepaid = (debtOf(id, borrower) - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD));
                require(
                    repaidUnits <= maxRepaid
                        || collateralOf[id][borrower][collateralIndex].mulDivDown(
                                liquidatedCollatPrice, ORACLE_PRICE_SCALE
                            ).mulDivDown(WAD, lif).zeroFloorSub(maxRepaid) < obligation.rcfThreshold,
                    "recovery close factor conditions violated"
                );
            }

            uint128 newCollateralOf = collateralOf[id][borrower][collateralIndex] - UtilsLib.toUint128(seizedAssets);
            collateralOf[id][borrower][collateralIndex] = newCollateralOf;
            if (newCollateralOf == 0 && seizedAssets > 0) {
                // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
                activatedCollaterals[id][borrower] &= ~uint128(1 << collateralIndex);
            }
            _obligationState.withdrawable += repaidUnits;
            // forge-lint: disable-next-line(unsafe-typecast)
            balanceOf[id][borrower] += int256(repaidUnits);
            require(balanceOf[id][borrower] <= 0, "repay too much");
        }

        emit EventsLib.Liquidate(msg.sender, id, collateralIndex, seizedAssets, repaidUnits, borrower, badDebt);

        SafeTransferLib.safeTransfer(obligation.collaterals[collateralIndex].token, msg.sender, seizedAssets);

        if (data.length > 0) {
            ICallbacks(msg.sender).onLiquidate(obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), repaidUnits);

        return (seizedAssets, repaidUnits);
    }

    function consume(bytes32 group, uint256 amount) external {
        consumed[msg.sender][group] += amount;

        emit EventsLib.Consume(msg.sender, group, amount);
    }

    /// @dev TODO: is it safe enough?
    function shuffleSession() external {
        bytes32 newSession = keccak256(abi.encode(session[msg.sender], blockhash(block.number - 1)));
        session[msg.sender] = newSession;

        emit EventsLib.ShuffleSession(msg.sender, newSession);
    }

    function setIsAuthorized(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
        emit EventsLib.SetIsAuthorized(msg.sender, authorized, newIsAuthorized);
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
            obligationState[id].fees = defaultFees[obligation.loanToken];
            obligationState[id].continuousFee = defaultContinuousFees[obligation.loanToken];
            // forge-lint: disable-next-line(unsafe-typecast)
            obligationState[id].lastUpdate = uint56(block.timestamp);
            IdLib.storeInCode(obligation);

            emit EventsLib.ObligationCreated(id, obligation);
        }
        return id;
    }

    function accrueFees(bytes32 id) public {
        ObligationState storage os = obligationState[id];
        uint256 elapsed = block.timestamp - os.lastUpdate;
        if (elapsed > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            os.lastUpdate = uint56(block.timestamp);

            uint256 fee = os.continuousFee;
            if (fee > 0) {
                uint256 feeFraction = elapsed * fee;
                os.lossIndex = WAD - (WAD - os.lossIndex).mulDivDown(WAD, WAD + feeFraction);
                os.accruedFees += (uint256(os.totalUnits) + os.withdrawable).mulDivDown(feeFraction, WAD + feeFraction);
            }
        }
    }

    function slash(bytes32 id, address user) public {
        uint256 _userLossIndex = userLossIndex[id][user];
        uint256 lossIndex = obligationState[id].lossIndex;
        if (_userLossIndex != lossIndex) {
            int256 balance = balanceOf[id][user];
            if (balance > 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                balanceOf[id][user] = int256(uint256(balance).mulDivDown(WAD - lossIndex, WAD - _userLossIndex));
            }
            userLossIndex[id][user] = lossIndex;
        }
    }

    function claimFees(Obligation memory obligation, uint256 amount, address receiver) external {
        require(msg.sender == continuousFeeRecipient, "unauthorized");
        bytes32 id = touchObligation(obligation);
        accrueFees(id);
        obligationState[id].accruedFees -= amount;
        obligationState[id].withdrawable -= amount;
        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, amount);

        emit EventsLib.ClaimFees(msg.sender, id, amount, receiver);
    }

    /// VIEW FUNCTIONS ///

    function toId(Obligation memory obligation) public view returns (bytes32) {
        return IdLib.toId(obligation, block.chainid, address(this));
    }

    /// @dev Returns the obligation corresponding to the given id.
    /// @dev Reverts if the id is not a valid id of a touched obligation.
    function toObligation(bytes32 id) public view returns (Obligation memory) {
        require(obligationState[id].created, "not created");
        address create2Address = address(uint160(uint256(id)));
        return abi.decode(create2Address.code, (Obligation));
    }

    function debtOf(bytes32 id, address user) public view returns (uint256) {
        return UtilsLib.negativePart(balanceOf[id][user]);
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

    function lastUpdate(bytes32 id) external view returns (uint256) {
        return obligationState[id].lastUpdate;
    }

    function tradingFees(bytes32 id) external view returns (uint16[7] memory) {
        return obligationState[id].fees;
    }

    function continuousFee(bytes32 id) external view returns (uint64) {
        return obligationState[id].continuousFee;
    }

    function accruedFees(bytes32 id) external view returns (uint256) {
        return obligationState[id].accruedFees;
    }

    function fees(bytes32 id) external view returns (uint16[7] memory) {
        return obligationState[id].fees;
    }

    /// @dev This function should be called with the id corresponding to the obligation.
    /// @dev This function does not call any oracle if debt is 0.
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        uint256 debt = debtOf(id, borrower);
        uint256 maxDebt;
        uint256 bitmap = activatedCollaterals[id][borrower];
        while (maxDebt < debt && bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            maxDebt += collateralOf[id][borrower][i].mulDivDown(price, ORACLE_PRICE_SCALE)
                .mulDivDown(collateral.lltv, WAD);
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
