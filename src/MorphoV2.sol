// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FeeLib} from "./libraries/FeeLib.sol";
import {WAD, ORACLE_PRICE_SCALE, MAX_LIF, TIME_TO_MAX_LIF} from "./libraries/ConstantsLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMorphoV2, Obligation, Offer, Signature, Collateral, Seizure} from "./interfaces/IMorphoV2.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

struct Callbacks {
    address buyerCallback;
    bytes buyerCallbackData;
    address sellerCallback;
    bytes sellerCallbackData;
}

struct Amounts {
    uint256 buyerAssets;
    uint256 sellerAssets;
    uint256 buyerObligationUnits;
    uint256 buyerObligationShares;
    uint256 sellerObligationUnits;
    uint256 sellerObligationShares;
}

struct FeeContext {
    uint256 feeRate;
    uint256 totalShares;
    uint256 totalUnits;
    uint256 sellerCost;
    uint256 sellerShares;
    uint256 buyerRevenue;
    uint256 buyerDebt;
    uint256 sellerPrice;
    uint256 buyerPrice;
}

/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
contract MorphoV2 is IMorphoV2 {
    using UtilsLib for uint256;

    /// STORAGE ///

    mapping(address user => mapping(bytes32 obligationId => uint256)) public sharesOf;
    mapping(address user => mapping(bytes32 obligationId => uint256)) public debtOf;
    mapping(bytes32 obligationId => uint256) public withdrawable;
    mapping(bytes32 obligationId => uint256) public totalUnits;
    mapping(bytes32 obligationId => uint256) public totalShares;
    mapping(address user => mapping(bytes32 obligationId => mapping(address collateralToken => uint256))) public
        collateralOf;

    /// @dev Groups are useful to have a global offered amount shared accross multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same assets, obligationUnits,
    /// obligationShares and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

    /// @dev Obligation trading fees for a given obligation id.
    /// @dev Bit 0: activated flag. Bits 1-144: 6 trading fees packed (24 bits each).
    /// @dev Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d.
    mapping(bytes32 obligationId => uint256) internal _obligationTradingFeeStorage;

    /// @dev Obligation interest fees for a given obligation id.
    mapping(bytes32 obligationId => uint256) public _obligationInterestFee;

    /// @dev Default trading fees per loan token. Used when obligation fee is not activated.
    /// @dev Bit 0: activated flag. Bits 1-144: 6 trading fees packed (24 bits each).
    /// @dev Fee indices: 0=0d, 1=1d, 2=7d, 3=30d, 4=90d, 5=180d.
    mapping(address loanToken => uint256) internal _defaultTradingFeeStorage;

    /// @dev Default interest fees per loan token.
    mapping(address loanToken => uint256) public _defaultInterestFee;

    address public feeRecipient;

    /// @dev Track not yet repaid cost for lenders and not yet repaid revenue for borrowers.
    mapping(address => mapping(bytes32 => uint256)) public costOf;
    mapping(address => mapping(bytes32 => uint256)) public revenueOf;

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

    function setObligationTradingFee(bytes32 id, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newTradingFee <= WAD, "Trading fee too high");
        require(index <= 5, "Invalid index");
        _obligationTradingFeeStorage[id] = FeeLib.setFee(_obligationTradingFeeStorage[id], index, newTradingFee);
        emit EventsLib.SetObligationTradingFee(id, index, newTradingFee);
    }

    function setObligationTradingFeeActivated(bytes32 id, bool activated) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        _obligationTradingFeeStorage[id] = FeeLib.setActivated(_obligationTradingFeeStorage[id], activated);
        emit EventsLib.SetObligationTradingFeeActivated(id, activated);
    }

    function setDefaultTradingFee(address loanToken, uint256 index, uint256 newTradingFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newTradingFee <= WAD, "Trading fee too high");
        require(index <= 5, "Invalid index");
        _defaultTradingFeeStorage[loanToken] = FeeLib.setFee(_defaultTradingFeeStorage[loanToken], index, newTradingFee);
        emit EventsLib.SetDefaultTradingFee(loanToken, index, newTradingFee);
    }

    function setDefaultTradingFeeActivated(address loanToken, bool activated) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        _defaultTradingFeeStorage[loanToken] = FeeLib.setActivated(_defaultTradingFeeStorage[loanToken], activated);
        emit EventsLib.SetDefaultTradingFeeActivated(loanToken, activated);
    }

    function setTradingFeeRecipient(address recipient) external {
        require(msg.sender == owner, "Only owner");
        feeRecipient = recipient;
        emit EventsLib.SetFeeRecipient(recipient);
    }

    function setObligationInterestFee(bytes32 id, uint256 newInterestFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newInterestFee <= WAD, "Interest fee too high");
        _obligationInterestFee[id] = newInterestFee;
        emit EventsLib.SetObligationInterestFee(id, newInterestFee);
    }

    function setDefaultInterestFee(address loanToken, uint256 newInterestFee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(newInterestFee <= WAD, "Interest fee too high");
        _defaultInterestFee[loanToken] = newInterestFee;
        emit EventsLib.SetDefaultInterestFee(loanToken, newInterestFee);
    }

    /// ENTRY-POINTS ///

    /// @dev Returns Amounts with all computed values.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev Neither the taker nor the maker can pass from having shares to having debt in one take.
    /// @dev The offer price is inclusive of the trading fee but not of the interest fee.
    /// @dev Input amounts are inclusive of both interest and trading fees.
    function take(
        Amounts memory amounts,
        address taker,
        Offer memory offer,
        Signature memory sig,
        bytes32 root,
        bytes32[] memory proof,
        address takerCallback,
        bytes memory takerCallbackData
    ) public returns (Amounts memory) {
        require(
            UtilsLib.atMostOneNonZero(
                amounts.buyerAssets,
                amounts.sellerAssets,
                amounts.buyerObligationUnits,
                amounts.buyerObligationShares,
                amounts.sellerObligationUnits,
                amounts.sellerObligationShares
            ),
            "inconsistent input"
        );
        require(
            UtilsLib.atMostOneNonZero(offer.assets, offer.obligationUnits, offer.obligationShares),
            "inconsistent offer input"
        );
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(offer.obligation.chainId == block.chainid, "chain id mismatch");
        require(offer.start < offer.expiry || offer.expiryPrice == offer.startPrice, "inconsistent prices");
        require(offer.maker != taker, "buyer and seller cannot be the same");
        require(signer(root, sig) == offer.maker, "invalid signature");
        require(UtilsLib.isLeaf(root, keccak256(abi.encode(offer)), proof), "invalid proof");
        require(offer.session == session[offer.maker], "invalid session");
        bytes32 id = toId(offer.obligation);

        Callbacks memory callbacks;
        address buyer;
        address seller;
        (
            buyer,
            callbacks.buyerCallback,
            callbacks.buyerCallbackData,
            seller,
            callbacks.sellerCallback,
            callbacks.sellerCallbackData
        ) = offer.buy
                ? (offer.maker, offer.callback, offer.callbackData, taker, takerCallback, takerCallbackData)
                : (taker, takerCallback, takerCallbackData, offer.maker, offer.callback, offer.callbackData);

        computeAmounts(id, offer, amounts, buyer, seller, offer.obligation.loanToken);

        bool buyerIsLender = (debtOf[buyer][id] == 0); // iff revenue of buyer == 0
        bool sellerIsBorrower = (sharesOf[seller][id] == 0); // iff cost of seller == 0

        if (buyerIsLender) {
            // Lender enters
            costOf[buyer][id] += amounts.buyerAssets;
            sharesOf[buyer][id] += amounts.buyerObligationShares;
        } else {
            // Borrower exits
            uint256 clearedRevenue = revenueOf[buyer][id].mulDivDown(amounts.buyerObligationUnits, debtOf[buyer][id]);
            revenueOf[buyer][id] -= clearedRevenue;
            debtOf[buyer][id] -= amounts.buyerObligationUnits;
        }

        if (sellerIsBorrower) {
            // Borrower enters
            revenueOf[seller][id] += amounts.sellerAssets;
            debtOf[seller][id] += amounts.sellerObligationUnits;
        } else {
            // Lender exits
            uint256 clearedCost = costOf[seller][id].mulDivDown(amounts.sellerObligationShares, sharesOf[seller][id]);
            costOf[seller][id] -= clearedCost;
            sharesOf[seller][id] -= amounts.sellerObligationShares;
        }

        if (buyerIsLender && sellerIsBorrower) {
            // Borrower enters + lender enters
            totalShares[id] += amounts.sellerObligationShares;
            totalUnits[id] += amounts.sellerObligationUnits;
        } else if (!buyerIsLender && !sellerIsBorrower) {
            // Borrower exits + lender exits
            totalShares[id] -= amounts.sellerObligationShares;
            totalUnits[id] -= amounts.buyerObligationUnits;
        } else if (!buyerIsLender && sellerIsBorrower) {
            // Borrower exits + lender enters
            totalUnits[id] += (amounts.sellerObligationUnits - amounts.buyerObligationUnits);
        } else if (buyerIsLender && !sellerIsBorrower) {
            // Lender enters + borrower exits
            totalShares[id] -= (amounts.sellerObligationShares - amounts.buyerObligationShares);
        }

        if (offer.assets > 0) {
            require(
                (consumed[offer.maker][offer.group] += offer.buy ? amounts.buyerAssets : amounts.sellerAssets)
                    <= offer.assets,
                "consumed"
            );
        } else if (offer.obligationUnits > 0) {
            require(
                (consumed[offer.maker][offer.group] += offer.buy
                            ? amounts.buyerObligationUnits
                            : amounts.sellerObligationUnits) <= offer.obligationUnits,
                "consumed"
            );
        } else {
            require(
                (consumed[offer.maker][offer.group] += offer.buy
                            ? amounts.buyerObligationShares
                            : amounts.sellerObligationShares) <= offer.obligationShares,
                "consumed"
            );
        }

        uint256 feeUnits = amounts.sellerObligationUnits - amounts.buyerObligationUnits;
        uint256 feeAssets = amounts.buyerAssets - amounts.sellerAssets;
        uint256 totalFee = feeUnits + feeAssets;
        if (totalFee > 0) {
            uint256 feeShares = totalFee.mulDivDown(totalShares[id], totalUnits[id]);
            sharesOf[feeRecipient][id] += feeShares;
            totalShares[id] += feeShares;
            totalUnits[id] += feeAssets;
            withdrawable[id] += feeAssets;
        }

        emit EventsLib.Take(
            msg.sender,
            id,
            amounts.buyerAssets,
            amounts.sellerAssets,
            amounts.buyerObligationUnits,
            amounts.sellerObligationUnits,
            taker
        );

        if (callbacks.buyerCallback != address(0)) {
            ICallbacks(callbacks.buyerCallback)
                .onBuy(
                    offer.obligation,
                    buyer,
                    amounts.buyerAssets,
                    amounts.sellerAssets,
                    amounts.buyerObligationUnits,
                    amounts.sellerObligationUnits,
                    callbacks.buyerCallbackData
                );
        }

        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, seller, amounts.sellerAssets);

        if (feeAssets > 0) {
            SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, address(this), feeAssets);
        }

        if (callbacks.sellerCallback != address(0)) {
            ICallbacks(callbacks.sellerCallback)
                .onSell(
                    offer.obligation,
                    seller,
                    amounts.buyerAssets,
                    amounts.sellerAssets,
                    amounts.buyerObligationUnits,
                    amounts.sellerObligationUnits,
                    callbacks.sellerCallbackData
                );
        }

        require(isHealthy(offer.obligation, seller), "Seller is unhealthy");

        return amounts;
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares, address onBehalf)
        external
        returns (uint256, uint256, uint256)
    {
        require(UtilsLib.atMostOneNonZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = toId(obligation);

        if (obligationUnits > 0) shares = obligationUnits.mulDivUp(totalShares[id] + 1, totalUnits[id] + 1);
        else obligationUnits = shares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);

        uint256 clearedCost = costOf[onBehalf][id].mulDivDown(shares, sharesOf[onBehalf][id]);
        uint256 interestFee =
            obligationUnits.zeroFloorSub(clearedCost).mulDivDown(getInterestFee(id, obligation.loanToken), WAD);

        costOf[onBehalf][id] -= clearedCost;
        sharesOf[onBehalf][id] -= shares;
        withdrawable[id] -= obligationUnits;
        totalShares[id] -= shares;
        totalUnits[id] -= obligationUnits;

        emit EventsLib.Withdraw(msg.sender, id, obligationUnits, shares, onBehalf);

        SafeTransferLib.safeTransfer(obligation.loanToken, msg.sender, obligationUnits - interestFee);
        SafeTransferLib.safeTransfer(obligation.loanToken, feeRecipient, interestFee);

        return (obligationUnits, obligationUnits - interestFee, shares);
    }

    function repay(Obligation memory obligation, uint256 obligationUnits, address onBehalf) external returns (uint256) {
        bytes32 id = toId(obligation);

        uint256 debt = debtOf[onBehalf][id];
        uint256 clearedRevenue;

        if (debt > 0) {
            // revenue <= debt so fee will always be zero
            clearedRevenue = revenueOf[onBehalf][id].mulDivDown(obligationUnits, debt);
            revenueOf[onBehalf][id] -= clearedRevenue;
        }

        debtOf[onBehalf][id] = debt - obligationUnits;
        withdrawable[id] += obligationUnits;

        emit EventsLib.Repay(msg.sender, id, obligationUnits, clearedRevenue, onBehalf);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), obligationUnits);

        return obligationUnits;
    }

    function supplyCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = toId(obligation);

        collateralOf[onBehalf][id][collateral] += assets;

        emit EventsLib.SupplyCollateral(msg.sender, id, collateral, assets, onBehalf);

        SafeTransferLib.safeTransferFrom(collateral, msg.sender, address(this), assets);
    }

    function withdrawCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        bytes32 id = toId(obligation);

        collateralOf[onBehalf][id][collateral] -= assets;

        require(isHealthy(obligation, onBehalf), "Unhealthy borrower");

        emit EventsLib.WithdrawCollateral(msg.sender, id, collateral, assets, onBehalf);

        SafeTransferLib.safeTransfer(collateral, msg.sender, assets);
    }

    /// @dev On each seizure at least one of `repaid` or `seized` should be equal to zero.
    /// @dev Accounts are liquidatable if they are unhealthy or if the maturity is reached.
    /// @dev If an account is healthy, the LIF grows linearly from 1 at maturity to MAX_LIF at maturity +
    /// TIME_TO_MAX_LIF.
    /// @param obligation The obligation.
    /// @param seizures An array of amounts of debt to repay or assets to seize with the index of the collateral in the
    /// obligation's collateral assets.
    /// @param borrower The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return A collection of the actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(Obligation memory obligation, Seizure[] memory seizures, address borrower, bytes calldata data)
        external
        returns (Seizure[] memory)
    {
        uint256 repayableDebt;
        uint256 maxDebt;
        bytes32 id = toId(obligation);
        uint256[] memory prices = new uint256[](obligation.collaterals.length);

        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            prices[i] = price;
            uint256 _collateralOf = collateralOf[borrower][id][_collateral.token];
            maxDebt += _collateralOf.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateral.lltv, WAD);
            repayableDebt += _collateralOf.mulDivUp(WAD, MAX_LIF).mulDivUp(price, ORACLE_PRICE_SCALE);
        }

        uint256 originalDebt = debtOf[borrower][id];
        require(block.timestamp > obligation.maturity || originalDebt > maxDebt, "position is not liquidatable");

        uint256 lif = originalDebt > maxDebt
            ? MAX_LIF
            : UtilsLib.min(MAX_LIF, WAD + (MAX_LIF - WAD) * (block.timestamp - obligation.maturity) / TIME_TO_MAX_LIF);

        uint256 badDebt = originalDebt.zeroFloorSub(repayableDebt);
        if (badDebt > 0) {
            debtOf[borrower][id] -= badDebt;
            totalUnits[id] -= badDebt;
        }

        uint256 totalRepaid;

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            require(UtilsLib.atMostOneNonZero(seizure.repaid, seizure.seized), "INCONSISTENT_INPUT");

            if (seizure.seized > 0) {
                seizure.repaid =
                    seizure.seized.mulDivUp(WAD, lif).mulDivUp(prices[seizure.collateralIndex], ORACLE_PRICE_SCALE);
            } else {
                seizure.seized =
                    seizure.repaid.mulDivDown(ORACLE_PRICE_SCALE, prices[seizure.collateralIndex]).mulDivDown(lif, WAD);
            }

            totalRepaid += seizure.repaid;
            address collateralToken = obligation.collaterals[seizure.collateralIndex].token;
            collateralOf[borrower][id][collateralToken] -= seizure.seized;
        }

        withdrawable[id] += totalRepaid;
        debtOf[borrower][id] -= totalRepaid;

        if (originalDebt > 0) {
            uint256 clearedRevenue = revenueOf[borrower][id].mulDivDown(badDebt + totalRepaid, originalDebt);
            revenueOf[borrower][id] -= clearedRevenue;
        }

        emit EventsLib.Liquidate(msg.sender, id, seizures, borrower, totalRepaid, badDebt);

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            SafeTransferLib.safeTransfer(
                obligation.collaterals[seizure.collateralIndex].token, msg.sender, seizure.seized
            );
        }

        if (data.length > 0) ICallbacks(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
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

    /// VIEW ///

    function getInterestFee(bytes32 id, address loanToken) public view returns (uint256) {
        return _obligationInterestFee[id] != 0 ? _obligationInterestFee[id] : _defaultInterestFee[loanToken];
    }

    function toId(Obligation memory obligation) public pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function isHealthy(Obligation memory obligation, address borrower) public view returns (bool) {
        bytes32 id = toId(obligation);
        uint256 debt = debtOf[borrower][id];
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                Collateral memory _collateral = obligation.collaterals[i];
                address collateralToken = _collateral.token;
                require(collateralToken > previousCollateralToken, "collaterals not sorted");
                maxDebt += collateralOf[borrower][id][collateralToken]
                    .mulDivDown(IOracle(_collateral.oracle).price(), ORACLE_PRICE_SCALE)
                    .mulDivDown(_collateral.lltv, WAD);
                previousCollateralToken = collateralToken;
            }
            return debt <= maxDebt;
        }
    }

    function signer(bytes32 root, Signature memory signature) internal pure returns (address) {
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", root));
        address tentativeSigner = ecrecover(messageHash, signature.v, signature.r, signature.s);
        require(tentativeSigner != address(0), "invalid signature");
        return tentativeSigner;
    }

    function computeAmounts(
        bytes32 id,
        Offer memory offer,
        Amounts memory amounts,
        address buyer,
        address seller,
        address loanToken
    ) internal view {
        uint256 offerPrice = offer.expiry != offer.start
            ? offer.startPrice + (offer.expiryPrice - offer.startPrice) * (block.timestamp - offer.start)
                / (offer.expiry - offer.start)
            : offer.startPrice;

        uint256 timeToMaturity =
            offer.obligation.maturity > block.timestamp ? offer.obligation.maturity - block.timestamp : 0;
        uint256 _tradingFee = tradingFee(id, offer.obligation.loanToken, timeToMaturity);
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + _tradingFee;
        // interest fees cannot bring price > 1 since they are fees on the profit
        require(buyerPrice <= WAD, "cannot trade at price above one");
        uint256 feeRate = getInterestFee(id, loanToken);
        uint256 _totalShares = totalShares[id];
        uint256 _totalUnits = totalUnits[id];
        uint256 _sellerCost = costOf[seller][id];
        uint256 _sellerShares = sharesOf[seller][id];
        uint256 _buyerRevenue = revenueOf[buyer][id];
        uint256 _buyerDebt = debtOf[buyer][id];

        if (amounts.sellerAssets > 0) {
            uint256 grossSellerUnits = amounts.sellerAssets.mulDivDown(WAD, sellerPrice);

            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerObligationUnits = amounts.sellerAssets * (WAD + sellerPrice * feeRate / WAD)
                        / sellerPrice * sxtu / (sxtu + _sellerCost * _totalShares * feeRate / WAD);
                } else {
                    amounts.sellerObligationUnits = grossSellerUnits;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerObligationUnits = amounts.sellerAssets * (WAD + buyerPrice * feeRate / WAD)
                        / sellerPrice * _buyerDebt / (_buyerDebt + _buyerRevenue * feeRate / WAD);
                } else {
                    amounts.buyerObligationUnits = grossSellerUnits;
                }
            }
            amounts.buyerAssets = amounts.sellerAssets.mulDivDown(buyerPrice, sellerPrice);
            amounts.sellerObligationShares = amounts.sellerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
            amounts.buyerObligationShares = amounts.buyerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
        } else if (amounts.sellerObligationUnits > 0) {
            uint256 grossSellerAssets = amounts.sellerObligationUnits.mulDivDown(sellerPrice, WAD);
            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerAssets = amounts.sellerObligationUnits
                        * (sellerPrice + _sellerCost * _totalShares * feeRate / sxtu) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.sellerAssets = grossSellerAssets;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerObligationUnits = amounts.sellerObligationUnits * (WAD + buyerPrice * feeRate / WAD)
                        / WAD * _buyerDebt / (_buyerDebt + _buyerRevenue * feeRate / WAD);
                } else {
                    amounts.buyerObligationUnits = amounts.sellerObligationUnits;
                }
            }
            amounts.buyerAssets = amounts.sellerObligationUnits.mulDivDown(buyerPrice, WAD);
            amounts.sellerObligationShares = amounts.sellerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
            amounts.buyerObligationShares = amounts.buyerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
        } else if (amounts.sellerObligationShares > 0) {
            amounts.sellerObligationUnits = amounts.sellerObligationShares.mulDivDown(_totalUnits + 1, _totalShares + 1);
            uint256 grossSellerAssets = amounts.sellerObligationUnits.mulDivDown(sellerPrice, WAD);
            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerAssets = amounts.sellerObligationUnits
                        * (sellerPrice + _sellerCost * _totalShares * feeRate / sxtu) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.sellerAssets = grossSellerAssets;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerObligationUnits = amounts.sellerObligationUnits * (WAD + buyerPrice * feeRate / WAD)
                        / WAD * _buyerDebt / (_buyerDebt + _buyerRevenue * feeRate / WAD);
                } else {
                    amounts.buyerObligationUnits = amounts.sellerObligationUnits;
                }
            }
            amounts.buyerAssets = amounts.sellerObligationUnits.mulDivDown(buyerPrice, WAD);
            amounts.buyerObligationShares = (amounts.buyerObligationUnits == amounts.sellerObligationUnits)
                ? amounts.sellerObligationShares
                : amounts.buyerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
        } else if (amounts.buyerAssets > 0) {
            uint256 grossBuyerUnits = amounts.buyerAssets.mulDivDown(WAD, buyerPrice);
            uint256 grossSellerAssets = amounts.buyerAssets.mulDivDown(sellerPrice, buyerPrice);
            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerAssets = amounts.buyerAssets
                        * (sellerPrice + _sellerCost * _totalShares * feeRate / sxtu) / buyerPrice * WAD
                        / (WAD + feeRate);
                } else {
                    amounts.sellerAssets = grossSellerAssets;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerObligationUnits = amounts.buyerAssets * (WAD + buyerPrice * feeRate / WAD) / buyerPrice
                        * _buyerDebt / (_buyerDebt + _buyerRevenue * feeRate / WAD);
                } else {
                    amounts.buyerObligationUnits = grossBuyerUnits;
                }
            }
            amounts.sellerObligationUnits = amounts.buyerAssets.mulDivDown(WAD, buyerPrice);
            amounts.sellerObligationShares = amounts.sellerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
            amounts.buyerObligationShares = amounts.buyerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
        } else if (amounts.buyerObligationUnits > 0) {
            uint256 grossSellerAssets = amounts.buyerObligationUnits.mulDivDown(sellerPrice, WAD);
            uint256 grossBuyerAssets = amounts.buyerObligationUnits.mulDivDown(buyerPrice, WAD);
            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerAssets = amounts.buyerObligationUnits
                        * (sellerPrice + _sellerCost * _totalShares * feeRate / sxtu) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.sellerAssets = grossSellerAssets;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerAssets = amounts.buyerObligationUnits
                        * (buyerPrice + _buyerRevenue * feeRate / _buyerDebt) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.buyerAssets = grossBuyerAssets;
                }
            }
            amounts.sellerObligationUnits = amounts.buyerObligationUnits;
            amounts.sellerObligationShares = amounts.sellerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
            amounts.buyerObligationShares = amounts.buyerObligationUnits.mulDivDown(_totalShares + 1, _totalUnits + 1);
        } else if (amounts.buyerObligationShares > 0) {
            amounts.buyerObligationUnits = amounts.buyerObligationShares.mulDivDown(_totalUnits + 1, _totalShares + 1);
            uint256 grossSellerAssets = amounts.buyerObligationUnits.mulDivDown(sellerPrice, WAD);
            uint256 grossBuyerAssets = amounts.buyerObligationUnits.mulDivDown(buyerPrice, WAD);
            {
                uint256 sxtu = _sellerShares * _totalUnits;
                bool sellerProfits = sxtu > 0
                    && sellerPrice.mulDivDown(_sellerShares, _totalShares) > _sellerCost.mulDivUp(WAD, _totalUnits);
                if (sellerProfits && feeRate > 0) {
                    amounts.sellerAssets = amounts.buyerObligationUnits
                        * (sellerPrice + _sellerCost * _totalShares * feeRate / sxtu) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.sellerAssets = grossSellerAssets;
                }
            }
            {
                bool buyerProfits = _buyerDebt > 0 && _buyerRevenue * WAD > buyerPrice * _buyerDebt;
                if (buyerProfits && feeRate > 0) {
                    amounts.buyerAssets = amounts.buyerObligationUnits
                        * (buyerPrice + _buyerRevenue * feeRate / _buyerDebt) / WAD * WAD / (WAD + feeRate);
                } else {
                    amounts.buyerAssets = grossBuyerAssets;
                }
            }
            amounts.sellerObligationUnits = amounts.buyerObligationUnits;
            amounts.sellerObligationShares = amounts.buyerObligationShares;
        }
    }

    /// @dev Return the trading fee using piecewise linear interpolation between breakpoints.
    /// @dev Returns 0 if neither obligation nor default fee is activated.
    function tradingFee(bytes32 id, address loanToken, uint256 timeToMaturity) public view returns (uint256) {
        uint256 feeStorage = _obligationTradingFeeStorage[id];
        if (!FeeLib.getActivated(feeStorage)) {
            feeStorage = _defaultTradingFeeStorage[loanToken];
            if (!FeeLib.getActivated(feeStorage)) return 0;
        }

        if (timeToMaturity >= 180 days) return FeeLib.getFee(feeStorage, 5);

        // forgefmt: disable-start
        (uint256 index, uint256 start, uint256 end) =
            timeToMaturity < 1 days ? (0, 0 days, 1 days) :
            timeToMaturity < 7 days ? (1, 1 days, 7 days) :
            timeToMaturity < 30 days ? (2, 7 days, 30 days) :
            timeToMaturity < 90 days ? (3, 30 days, 90 days) :
            (4, 90 days, 180 days);
        // forgefmt: disable-end

        uint256 feeLower = FeeLib.getFee(feeStorage, index);
        uint256 feeUpper = FeeLib.getFee(feeStorage, index + 1);

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
