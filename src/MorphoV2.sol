// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {
    WAD,
    ORACLE_PRICE_SCALE,
    FEE_STEP,
    MAX_FEE,
    MAX_LIF,
    TIME_TO_MAX_LIF,
    EIP712_DOMAIN_TYPEHASH,
    ROOT_TYPEHASH
} from "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMorphoV2, Obligation, Offer, Signature, Collateral, ObligationStorage} from "./interfaces/IMorphoV2.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
contract MorphoV2 is IMorphoV2 {
    using UtilsLib for uint256;

    /// STORAGE ///

    mapping(bytes32 id => mapping(address user => uint256)) public sharesOf;
    mapping(bytes32 id => mapping(address user => uint256)) public debtOf;
    mapping(bytes32 id => mapping(address user => mapping(address collateralToken => uint256))) public collateralOf;
    mapping(bytes32 id => ObligationStorage) public obligationStorage;

    /// @dev Groups are useful to have a global offered amount shared accross multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same assets, obligationUnits,
    /// obligationShares and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

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
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        require(
            newTradingFee <= uint256(obligationStorage[id].fees[index]) * FEE_STEP,
            "New trading fee is higher than current"
        );
        // forge-lint: disable-next-line(unsafe-typecast) as newTradingFee is less than MAX_FEE
        obligationStorage[id].fees[index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    /// @dev Doesn't change the fee of already created obligations.
    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newTradingFee <= MAX_FEE, "Trading fee too high");
        require(index <= 5, "Invalid index");
        require(newTradingFee % FEE_STEP == 0, "fee should be a multiple of FEE_STEP");
        // forge-lint: disable-next-line(unsafe-typecast) as newTradingFee is less than MAX_FEE
        defaultFees[loanToken][index] = uint16(newTradingFee / FEE_STEP);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setTradingFeeRecipient(address recipient) external {
        require(msg.sender == owner, "Only owner");
        tradingFeeRecipient = recipient;
        emit EventsLib.SetTradingFeeRecipient(recipient);
    }

    /// ENTRY-POINTS ///

    /// @dev Returns buyerAssets, sellerAssets, obligationUnits, obligationShares.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev Neither the taker nor the maker can pass from having shares to having debt in one take.
    function take(
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        Offer memory offer,
        Signature memory sig,
        bytes32 root,
        bytes32[] memory proof,
        address takerCallback,
        bytes memory takerCallbackData
    ) public returns (uint256, uint256, uint256, uint256) {
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
        ObligationStorage storage _obligationStorage = obligationStorage[id];

        (
            address buyer,
            address buyerCallback,
            bytes memory buyerCallbackData,
            address seller,
            address sellerCallback,
            bytes memory sellerCallbackData
        ) = offer.buy
            ? (offer.maker, offer.callback, offer.callbackData, taker, takerCallback, takerCallbackData)
            : (taker, takerCallback, takerCallbackData, offer.maker, offer.callback, offer.callbackData);

        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        uint256 _tradingFee = tradingFee(id, timeToMaturity);
        uint256 sellerPrice = offer.buy ? offer.price - _tradingFee : offer.price;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        require(buyerPrice <= WAD, "cannot trade at price above one");

        if (buyerAssets > 0) {
            obligationUnits = buyerAssets.mulDivDown(WAD, buyerPrice);
            sellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
            obligationShares =
                obligationUnits.mulDivDown(_obligationStorage.totalShares + 1, _obligationStorage.totalUnits + 1);
        } else if (sellerAssets > 0) {
            obligationUnits = sellerAssets.mulDivDown(WAD, sellerPrice);
            buyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
            obligationShares =
                obligationUnits.mulDivDown(_obligationStorage.totalShares + 1, _obligationStorage.totalUnits + 1);
        } else if (obligationUnits > 0) {
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
            obligationShares =
                obligationUnits.mulDivDown(_obligationStorage.totalShares + 1, _obligationStorage.totalUnits + 1);
        } else {
            obligationUnits =
                obligationShares.mulDivDown(_obligationStorage.totalUnits + 1, _obligationStorage.totalShares + 1);
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
        }

        if (offer.assets > 0) {
            require(
                (consumed[offer.maker][offer.group] += offer.buy ? buyerAssets : sellerAssets) <= offer.assets,
                "consumed"
            );
        } else if (offer.obligationUnits > 0) {
            require((consumed[offer.maker][offer.group] += obligationUnits) <= offer.obligationUnits, "consumed");
        } else {
            require((consumed[offer.maker][offer.group] += obligationShares) <= offer.obligationShares, "consumed");
        }

        bool buyerIsLender = (debtOf[id][buyer] == 0);
        bool sellerIsBorrower = (sharesOf[id][seller] == 0);
        if (buyerIsLender && sellerIsBorrower) {
            // Lender enters + borrower enters.
            sharesOf[id][buyer] += obligationShares;
            debtOf[id][seller] += obligationUnits;
            _obligationStorage.totalShares += UtilsLib.toUint128(obligationShares);
            _obligationStorage.totalUnits += UtilsLib.toUint128(obligationUnits);
        } else if (buyerIsLender && !sellerIsBorrower) {
            // Lender enters + lender exits.
            sharesOf[id][buyer] += obligationShares;
            sharesOf[id][seller] -= obligationShares;
        } else if (!buyerIsLender && sellerIsBorrower) {
            // Borrower exits + borrower enters.
            debtOf[id][buyer] -= obligationUnits;
            debtOf[id][seller] += obligationUnits;
        } else {
            // Borrower exits + lender exits.
            debtOf[id][buyer] -= obligationUnits;
            sharesOf[id][seller] -= obligationShares;
            _obligationStorage.totalShares -= UtilsLib.toUint128(obligationShares);
            _obligationStorage.totalUnits -= UtilsLib.toUint128(obligationUnits);
        }

        emit EventsLib.Take(
            msg.sender,
            id,
            buyerAssets,
            sellerAssets,
            obligationUnits,
            obligationShares,
            taker,
            buyerIsLender,
            sellerIsBorrower
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
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, seller, sellerAssets);

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

        require(isHealthy(offer.obligation, seller), "Seller is unhealthy");

        return (buyerAssets, sellerAssets, obligationUnits, obligationShares);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares, address onBehalf)
        external
        returns (uint256, uint256)
    {
        require(UtilsLib.atMostOneNonZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = touchObligation(obligation);
        ObligationStorage storage _obligationStorage = obligationStorage[id];

        if (obligationUnits > 0) {
            shares = obligationUnits.mulDivUp(_obligationStorage.totalShares + 1, _obligationStorage.totalUnits + 1);
        } else {
            obligationUnits = shares.mulDivDown(_obligationStorage.totalUnits + 1, _obligationStorage.totalShares + 1);
        }

        sharesOf[id][onBehalf] -= shares;
        _obligationStorage.withdrawable -= obligationUnits;
        _obligationStorage.totalShares -= UtilsLib.toUint128(shares);
        _obligationStorage.totalUnits -= UtilsLib.toUint128(obligationUnits);

        emit EventsLib.Withdraw(msg.sender, id, obligationUnits, shares, onBehalf);

        SafeTransferLib.safeTransfer(obligation.loanToken, msg.sender, obligationUnits);

        return (obligationUnits, shares);
    }

    function repay(Obligation memory obligation, uint256 obligationUnits, address onBehalf) external {
        bytes32 id = touchObligation(obligation);

        debtOf[id][onBehalf] -= obligationUnits;
        obligationStorage[id].withdrawable += obligationUnits;

        emit EventsLib.Repay(msg.sender, id, obligationUnits, onBehalf);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), obligationUnits);
    }

    function supplyCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = touchObligation(obligation);

        collateralOf[id][onBehalf][collateral] += assets;

        emit EventsLib.SupplyCollateral(msg.sender, id, collateral, assets, onBehalf);

        SafeTransferLib.safeTransferFrom(collateral, msg.sender, address(this), assets);
    }

    function withdrawCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = touchObligation(obligation);

        collateralOf[id][onBehalf][collateral] -= assets;

        require(isHealthy(obligation, onBehalf), "Unhealthy borrower");

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateral, assets, onBehalf);

        SafeTransferLib.safeTransfer(collateral, msg.sender, assets);
    }

    /// @dev At least one of `repaidUnits` or `seizedAssets` should be equal to zero.
    /// @dev Accounts are liquidatable if they are unhealthy or if the maturity is reached.
    /// @dev Before maturity, the liquidation cannot put the borrower back into health (recovery close factory).
    /// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to MAX_LIF at maturity +
    /// TIME_TO_MAX_LIF.
    /// @dev Returns repaid units and seized assets.
    function liquidate(
        Obligation calldata obligation,
        uint256 collateralIndex,
        uint256 repaidUnits,
        uint256 seizedAssets,
        address borrower,
        bytes calldata data
    ) external returns (uint256, uint256) {
        require(UtilsLib.atMostOneNonZero(repaidUnits, seizedAssets), "INCONSISTENT_INPUT");
        bytes32 id = touchObligation(obligation);
        ObligationStorage storage _obligationStorage = obligationStorage[id];

        uint256 repayableDebt;
        uint256 maxDebt;
        uint256 liquidatedCollateralPrice;
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            if (i == collateralIndex) liquidatedCollateralPrice = price;
            uint256 _collateralOf = collateralOf[id][borrower][_collateral.token];
            maxDebt += _collateralOf.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateral.lltv, WAD);
            repayableDebt += _collateralOf.mulDivUp(WAD, MAX_LIF).mulDivUp(price, ORACLE_PRICE_SCALE);
        }

        uint256 originalDebt = debtOf[id][borrower];
        require(block.timestamp > obligation.maturity || originalDebt > maxDebt, "position is not liquidatable");

        uint256 badDebt = originalDebt.zeroFloorSub(repayableDebt);
        if (badDebt > 0) {
            debtOf[id][borrower] -= badDebt;
            _obligationStorage.totalUnits -= UtilsLib.toUint128(badDebt);
        }

        if (repaidUnits > 0 || seizedAssets > 0) {
            uint256 lif = originalDebt > maxDebt
                ? MAX_LIF
                : UtilsLib.min(
                    MAX_LIF, WAD + (MAX_LIF - WAD) * (block.timestamp - obligation.maturity) / TIME_TO_MAX_LIF
                );

            if (seizedAssets > 0) {
                repaidUnits = seizedAssets.mulDivUp(WAD, lif).mulDivUp(liquidatedCollateralPrice, ORACLE_PRICE_SCALE);
            } else {
                seizedAssets =
                    repaidUnits.mulDivDown(ORACLE_PRICE_SCALE, liquidatedCollateralPrice).mulDivDown(lif, WAD);
            }

            uint256 newMaxDebt = maxDebt
                - seizedAssets.mulDivDown(liquidatedCollateralPrice, ORACLE_PRICE_SCALE)
                    .mulDivDown(obligation.collaterals[collateralIndex].lltv, WAD);
            require(
                block.timestamp > obligation.maturity || originalDebt - repaidUnits >= newMaxDebt,
                "recovery close factory violated"
            );

            collateralOf[id][borrower][obligation.collaterals[collateralIndex].token] -= seizedAssets;
            _obligationStorage.withdrawable += repaidUnits;
            debtOf[id][borrower] -= repaidUnits;
        }

        emit EventsLib.Liquidate(msg.sender, id, collateralIndex, seizedAssets, repaidUnits, borrower, badDebt);

        SafeTransferLib.safeTransfer(obligation.collaterals[collateralIndex].token, msg.sender, seizedAssets);

        if (data.length > 0) {
            ICallbacks(msg.sender).onLiquidate(obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
        }

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), repaidUnits);

        return (repaidUnits, seizedAssets);
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

    function flashLoan(address token, uint256 assets, address callback, bytes calldata data) external {
        emit EventsLib.FlashLoan(msg.sender, token, assets);

        SafeTransferLib.safeTransfer(token, msg.sender, assets);

        IFlashLoanCallback(callback).onFlashLoan(token, assets, data);

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), assets);
    }

    /// @dev Returns the obligation id and creates the obligation if it doesn't exist yet.
    function touchObligation(Obligation memory obligation) public returns (bytes32) {
        bytes32 id = toId(obligation);
        if (!obligationStorage[id].created) {
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                address collateralToken = obligation.collaterals[i].token;
                require(collateralToken > previousCollateralToken, "collaterals not sorted");
                previousCollateralToken = collateralToken;
            }

            obligationStorage[id].created = true;
            obligationStorage[id].fees = defaultFees[obligation.loanToken];

            emit EventsLib.ObligationCreated(id, obligation);
        }
        return id;
    }

    /// VIEW FUNCTIONS ///

    function totalUnits(bytes32 id) external view returns (uint256) {
        return obligationStorage[id].totalUnits;
    }

    function totalShares(bytes32 id) external view returns (uint256) {
        return obligationStorage[id].totalShares;
    }

    function obligationCreated(bytes32 id) external view returns (bool) {
        return obligationStorage[id].created;
    }

    function withdrawable(bytes32 id) external view returns (uint256) {
        return obligationStorage[id].withdrawable;
    }

    function fees(bytes32 id) external view returns (uint16[6] memory) {
        return obligationStorage[id].fees;
    }

    function toId(Obligation memory obligation) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), obligation));
    }

    function isHealthy(Obligation memory obligation, address borrower) public view returns (bool) {
        bytes32 id = toId(obligation);
        uint256 debt = debtOf[id][borrower];
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                Collateral memory _collateral = obligation.collaterals[i];
                maxDebt += collateralOf[id][borrower][_collateral.token]
                    .mulDivDown(IOracle(_collateral.oracle).price(), ORACLE_PRICE_SCALE)
                    .mulDivDown(_collateral.lltv, WAD);
            }
            return (debt <= maxDebt) && (maxDebt >= obligation.minCollateral);
        }
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
        uint16[6] memory _fees = obligationStorage[id].fees;

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
