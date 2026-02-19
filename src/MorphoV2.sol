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
    MAX_FEE,
    MAX_LIF,
    TIME_TO_MAX_LIF,
    MAX_COLLATERALS,
    MAX_COLLATERALS_PER_BORROWER,
    EIP712_DOMAIN_TYPEHASH,
    ROOT_TYPEHASH
} from "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {
    IMorphoV2,
    Obligation,
    Offer,
    Signature,
    Collateral,
    BorrowerState,
    ObligationState
} from "./interfaces/IMorphoV2.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
contract MorphoV2 is IMorphoV2 {
    using UtilsLib for uint256;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => uint256)) public sharesOf;
    mapping(bytes32 id => mapping(address user => BorrowerState)) public borrowerState;
    mapping(bytes32 id => mapping(address user => mapping(address collateralToken => uint256))) public collateralOf;
    mapping(bytes32 id => ObligationState) public obligationState;

    /// @dev Groups are useful to have a global offered amount shared accross multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same assets, obligationUnits,
    /// obligationShares and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

    /// @dev Whether an address is authorized to manage positions on behalf of another address.
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;

    /// @dev Default fees per loan token. Set when the obligation is created. Can be later decreased by the feeSetter.
    mapping(address loanToken => uint16[6]) public defaultFees;

    address public tradingFeeRecipient;

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
        require(msg.sender == owner, "Only owner");
        owner = newOwner;
        emit EventsLib.SetOwner(newOwner);
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == owner, "Only owner");
        feeSetter = newFeeSetter;
        emit EventsLib.SetFeeSetter(newFeeSetter);
    }

    /// @dev Overrides the fee of a specific obligation.
    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(index <= 5, "Invalid index");
        require(newTradingFee <= MAX_FEE, "Trading fee too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee is less than MAX_FEE
        obligationState[id].fees[index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    /// @dev Doesn't change the fee of already created obligations.
    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(index <= 5, "Invalid index");
        require(newTradingFee <= MAX_FEE, "Trading fee too high");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-item(unsafe-typecast) as newTradingFee is less than MAX_FEE
        defaultFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setTradingFeeRecipient(address feeRecipient) external {
        require(msg.sender == owner, "Only owner");
        tradingFeeRecipient = feeRecipient;
        emit EventsLib.SetTradingFeeRecipient(feeRecipient);
    }

    /// ENTRY-POINTS ///

    /// @dev Returns buyerAssets, sellerAssets, obligationUnits, obligationShares.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev Neither the taker nor the maker can pass from having shares to having debt in one take.
    /// @dev The taker might not get the price they expected if the trading fee was just changed.
    function take(
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes memory takerCallbackData,
        address receiverIfTakerIsSeller,
        Offer memory offer,
        Signature memory sig,
        bytes32 root,
        bytes32[] memory proof
    ) external returns (uint256, uint256, uint256, uint256) {
        require(taker == msg.sender || isAuthorized[taker][msg.sender], "UNAUTHORIZED");
        require(
            UtilsLib.atMostOneNonZero(buyerAssets, sellerAssets, obligationUnits, obligationShares),
            "inconsistent input"
        );
        require(
            UtilsLib.atMostOneNonZero(offer.assets, offer.obligationUnits, offer.obligationShares),
            "inconsistent offer input"
        );
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(offer.maker != taker, "buyer and seller cannot be the same");
        require(signer(root, sig) == offer.maker, "invalid signature");
        require(UtilsLib.isLeaf(root, keccak256(abi.encode(offer)), proof), "invalid proof");
        require(offer.session == session[offer.maker], "invalid session");
        bytes32 id = touchObligation(offer.obligation);
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

        if (buyerAssets > 0) {
            obligationUnits = buyerAssets.mulDivDown(WAD, buyerPrice);
            sellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
            obligationShares =
                obligationUnits.mulDivDown(_obligationState.totalShares + 1, _obligationState.totalUnits + 1);
        } else if (sellerAssets > 0) {
            obligationUnits = sellerAssets.mulDivDown(WAD, sellerPrice);
            buyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
            obligationShares =
                obligationUnits.mulDivDown(_obligationState.totalShares + 1, _obligationState.totalUnits + 1);
        } else if (obligationUnits > 0) {
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
            obligationShares =
                obligationUnits.mulDivDown(_obligationState.totalShares + 1, _obligationState.totalUnits + 1);
        } else {
            obligationUnits =
                obligationShares.mulDivDown(_obligationState.totalUnits + 1, _obligationState.totalShares + 1);
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        }

        uint256 newConsumed;
        if (offer.assets > 0) {
            newConsumed = consumed[offer.maker][offer.group] += offer.buy ? buyerAssets : sellerAssets;
            require(newConsumed <= offer.assets, "consumed");
        } else if (offer.obligationUnits > 0) {
            newConsumed = consumed[offer.maker][offer.group] += obligationUnits;
            require(newConsumed <= offer.obligationUnits, "consumed");
        } else {
            newConsumed = consumed[offer.maker][offer.group] += obligationShares;
            require(newConsumed <= offer.obligationShares, "consumed");
        }

        bool buyerIsLender = (borrowerState[id][buyer].debt == 0);
        bool sellerIsBorrower = (sharesOf[id][seller] == 0);
        if (buyerIsLender && sellerIsBorrower) {
            // Lender enters + borrower enters.
            sharesOf[id][buyer] += obligationShares;
            borrowerState[id][seller].debt += UtilsLib.toUint128(obligationUnits);
            _obligationState.totalShares += UtilsLib.toUint128(obligationShares);
            _obligationState.totalUnits += UtilsLib.toUint128(obligationUnits);
        } else if (buyerIsLender && !sellerIsBorrower) {
            // Lender enters + lender exits.
            sharesOf[id][buyer] += obligationShares;
            sharesOf[id][seller] -= obligationShares;
        } else if (!buyerIsLender && sellerIsBorrower) {
            // Borrower exits + borrower enters.
            borrowerState[id][buyer].debt -= UtilsLib.toUint128(obligationUnits);
            borrowerState[id][seller].debt += UtilsLib.toUint128(obligationUnits);
        } else {
            // Borrower exits + lender exits.
            borrowerState[id][buyer].debt -= UtilsLib.toUint128(obligationUnits);
            sharesOf[id][seller] -= obligationShares;
            _obligationState.totalShares -= UtilsLib.toUint128(obligationShares);
            _obligationState.totalUnits -= UtilsLib.toUint128(obligationUnits);
        }

        emit EventsLib.Take(
            msg.sender,
            id,
            offer.maker,
            taker,
            offer.buy,
            buyerAssets,
            sellerAssets,
            obligationUnits,
            obligationShares,
            buyerIsLender,
            sellerIsBorrower,
            receiver,
            offer.group,
            newConsumed
        );

        if (buyerCallback != address(0)) {
            ICallbacks(buyerCallback)
                .onBuy(
                    offer.obligation,
                    buyer,
                    buyerAssets,
                    sellerAssets,
                    obligationUnits,
                    obligationShares,
                    buyerCallbackData
                );
        }

        SafeTransferLib.safeTransferFrom(
            offer.obligation.loanToken, buyer, tradingFeeRecipient, buyerAssets - sellerAssets
        );
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, receiver, sellerAssets);

        if (sellerCallback != address(0)) {
            ICallbacks(sellerCallback)
                .onSell(
                    offer.obligation,
                    seller,
                    buyerAssets,
                    sellerAssets,
                    obligationUnits,
                    obligationShares,
                    sellerCallbackData
                );
        }

        require(isHealthy(offer.obligation, id, seller), "Seller is unhealthy");

        return (buyerAssets, sellerAssets, obligationUnits, obligationShares);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(
        Obligation memory obligation,
        uint256 obligationUnits,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "UNAUTHORIZED");
        require(UtilsLib.atMostOneNonZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];

        if (obligationUnits > 0) {
            shares = obligationUnits.mulDivUp(_obligationState.totalShares + 1, _obligationState.totalUnits + 1);
        } else {
            obligationUnits = shares.mulDivDown(_obligationState.totalUnits + 1, _obligationState.totalShares + 1);
        }

        sharesOf[id][onBehalf] -= shares;
        _obligationState.withdrawable -= obligationUnits;
        _obligationState.totalShares -= UtilsLib.toUint128(shares);
        _obligationState.totalUnits -= UtilsLib.toUint128(obligationUnits);

        emit EventsLib.Withdraw(msg.sender, id, obligationUnits, shares, onBehalf, receiver);

        SafeTransferLib.safeTransfer(obligation.loanToken, receiver, obligationUnits);

        return (obligationUnits, shares);
    }

    function repay(Obligation memory obligation, uint256 obligationUnits, address onBehalf) external {
        bytes32 id = touchObligation(obligation);

        borrowerState[id][onBehalf].debt -= UtilsLib.toUint128(obligationUnits);
        obligationState[id].withdrawable += obligationUnits;

        emit EventsLib.Repay(msg.sender, id, obligationUnits, onBehalf);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), obligationUnits);
    }

    function supplyCollateral(Obligation memory obligation, uint256 collateralIndex, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collaterals[collateralIndex].token;

        uint256 newCollateralOf = collateralOf[id][onBehalf][collateralToken] + assets;
        collateralOf[id][onBehalf][collateralToken] = newCollateralOf;

        if (newCollateralOf == assets && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            uint128 newBitmap = borrowerState[id][onBehalf].activatedCollaterals | uint128(1 << collateralIndex);
            borrowerState[id][onBehalf].activatedCollaterals = newBitmap;
            require(UtilsLib.countBits(newBitmap) <= MAX_COLLATERALS_PER_BORROWER, "too many collaterals per borrower");
        }

        require(
            newCollateralOf == 0
                || newCollateralOf.mulDivDown(
                        IOracle(obligation.collaterals[collateralIndex].oracle).price(), ORACLE_PRICE_SCALE
                    ) >= obligation.minCollatValue,
            "Below min collateral"
        );

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
        require(onBehalf == msg.sender || isAuthorized[onBehalf][msg.sender], "UNAUTHORIZED");
        bytes32 id = touchObligation(obligation);
        address collateralToken = obligation.collaterals[collateralIndex].token;

        uint256 newCollateralOf = collateralOf[id][onBehalf][collateralToken] - assets;
        collateralOf[id][onBehalf][collateralToken] = newCollateralOf;

        if (newCollateralOf == 0 && assets > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
            borrowerState[id][onBehalf].activatedCollaterals &= ~uint128(1 << collateralIndex);
        }

        require(isHealthy(obligation, id, onBehalf), "Unhealthy borrower");
        require(
            newCollateralOf == 0
                || newCollateralOf.mulDivDown(
                        IOracle(obligation.collaterals[collateralIndex].oracle).price(), ORACLE_PRICE_SCALE
                    ) >= obligation.minCollatValue,
            "Below min collateral"
        );

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateralToken, assets, onBehalf, receiver);

        SafeTransferLib.safeTransfer(collateralToken, receiver, assets);
    }

    /// @dev At least one of `seizedAssets` or `repaidUnits` should be equal to zero.
    /// @dev Accounts are liquidatable if they are unhealthy or if the maturity has passed.
    /// @dev Before maturity, the liquidation cannot put the borrower back into health (recovery close factor).
    /// @dev In that case, we want debtOf - repaidUnits >= maxDebt - repaidUnits*LIF*LLTV, which is equivalent to
    /// repaidUnits <= (debtOf-maxDebt) / (1 - LIF*LLTV).
    /// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to MAX_LIF at maturity +
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
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), "INCONSISTENT_INPUT");
        bytes32 id = touchObligation(obligation);
        ObligationState storage _obligationState = obligationState[id];
        address liquidatedCollatToken = obligation.collaterals[collateralIndex].token;

        uint256 repayableDebt;
        uint256 maxDebt;
        uint256 liquidatedCollatPrice;
        BorrowerState storage _state = borrowerState[id][borrower];
        uint256 bitmap = _state.activatedCollaterals;
        while (bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            if (i == collateralIndex) liquidatedCollatPrice = price;
            uint256 _collateralOf = collateralOf[id][borrower][_collateral.token];
            maxDebt += _collateralOf.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateral.lltv, WAD);
            repayableDebt += _collateralOf.mulDivUp(WAD, MAX_LIF).mulDivUp(price, ORACLE_PRICE_SCALE);
            bitmap ^= (1 << i);
        }

        uint256 originalDebt = _state.debt;
        require(block.timestamp > obligation.maturity || originalDebt > maxDebt, "position is not liquidatable");

        uint256 badDebt = originalDebt.zeroFloorSub(repayableDebt);
        if (badDebt > 0) {
            _state.debt -= UtilsLib.toUint128(badDebt);
            _obligationState.totalUnits -= UtilsLib.toUint128(badDebt);
        }

        if (repaidUnits > 0 || seizedAssets > 0) {
            uint256 lif = originalDebt > maxDebt
                ? MAX_LIF
                : UtilsLib.min(
                    MAX_LIF, WAD + (MAX_LIF - WAD) * (block.timestamp - obligation.maturity) / TIME_TO_MAX_LIF
                );

            if (seizedAssets > 0) {
                repaidUnits = seizedAssets.mulDivUp(WAD, lif).mulDivUp(liquidatedCollatPrice, ORACLE_PRICE_SCALE);
            } else {
                seizedAssets = repaidUnits.mulDivDown(ORACLE_PRICE_SCALE, liquidatedCollatPrice).mulDivDown(lif, WAD);
            }

            if (block.timestamp <= obligation.maturity) {
                uint256 lltv = obligation.collaterals[collateralIndex].lltv;
                // Rounded up to avoid consecutive max liquidations.
                // Acknowledged that the position could be slightly healthy after a liquidation.
                uint256 maxRepaid = (uint256(_state.debt) - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD));
                require(repaidUnits <= maxRepaid, "recovery close factor violated");
            }

            collateralOf[id][borrower][liquidatedCollatToken] -= seizedAssets;
            if (collateralOf[id][borrower][liquidatedCollatToken] == 0 && seizedAssets > 0) {
                // forge-lint: disable-next-item(unsafe-typecast) as collateralIndex < MAX_COLLATERALS (128)
                _state.activatedCollaterals &= ~uint128(1 << collateralIndex);
            }
            _obligationState.withdrawable += repaidUnits;
            _state.debt -= UtilsLib.toUint128(repaidUnits);
        }

        emit EventsLib.Liquidate(msg.sender, id, collateralIndex, seizedAssets, repaidUnits, borrower, badDebt);

        SafeTransferLib.safeTransfer(liquidatedCollatToken, msg.sender, seizedAssets);

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
            require(obligation.collaterals.length <= MAX_COLLATERALS, "too many collaterals");
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                address collateralToken = obligation.collaterals[i].token;
                require(collateralToken > previousCollateralToken, "collaterals not sorted");
                require(obligation.collaterals[i].lltv < WAD.mulDivDown(WAD, MAX_LIF), "lltv too high or LIF too high"); // temporary.
                previousCollateralToken = collateralToken;
            }

            obligationState[id].created = true;
            obligationState[id].fees = defaultFees[obligation.loanToken];
            IdLib.storeInCode(obligation);

            emit EventsLib.ObligationCreated(id, obligation);
        }
        return id;
    }

    /// VIEW FUNCTIONS ///

    function debtOf(bytes32 id, address user) external view returns (uint256) {
        return borrowerState[id][user].debt;
    }

    function activatedCollaterals(bytes32 id, address user) external view returns (uint256) {
        return borrowerState[id][user].activatedCollaterals;
    }

    function totalUnits(bytes32 id) external view returns (uint256) {
        return obligationState[id].totalUnits;
    }

    function totalShares(bytes32 id) external view returns (uint256) {
        return obligationState[id].totalShares;
    }

    function obligationCreated(bytes32 id) external view returns (bool) {
        return obligationState[id].created;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return obligationState[id].withdrawable;
    }

    function fees(bytes32 id) external view returns (uint16[6] memory) {
        return obligationState[id].fees;
    }

    /// @dev This function should be called with the id corresponding to the obligation.
    /// @dev This function does not call any oracle if debt is 0.
    function isHealthy(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        BorrowerState storage _borrowerState = borrowerState[id][borrower];
        uint256 debt = _borrowerState.debt;
        uint256 maxDebt;
        uint256 bitmap = _borrowerState.activatedCollaterals;
        while (maxDebt < debt && bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            maxDebt += collateralOf[id][borrower][collateral.token].mulDivDown(price, ORACLE_PRICE_SCALE)
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

    /// @dev Returns the trading fee using piecewise linear interpolation between breakpoints.
    function tradingFee(bytes32 id, uint256 timeToMaturity) public view returns (uint256) {
        uint16[6] memory _fees = obligationState[id].fees;

        if (timeToMaturity >= 180 days) return uint256(_fees[5]) * FEE_STEP;

        // forgefmt: disable-start
        (uint256 index, uint256 start, uint256 end) =
            timeToMaturity < 1 days  ? (0, 0 days, 1 days) :
            timeToMaturity < 7 days  ? (1, 1 days, 7 days) :
            timeToMaturity < 30 days ? (2, 7 days, 30 days) :
            timeToMaturity < 90 days ? (3, 30 days, 90 days) :
                                       (4, 90 days, 180 days);
        // forgefmt: disable-end

        uint256 feeLower = uint256(_fees[index]) * FEE_STEP;
        uint256 feeUpper = uint256(_fees[index + 1]) * FEE_STEP;

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
