// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {WAD, ORACLE_PRICE_SCALE, LIQUIDATION_INCENTIVE_FACTOR} from "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IMorphoV2, Obligation, Offer, Signature, Seizure} from "./interfaces/IMorphoV2.sol";
import {ICallbacks} from "./interfaces/ICallbacks.sol";

/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
contract MorphoV2 is IMorphoV2 {
    using MathLib for uint256;

    /// STORAGE ///

    mapping(address => mapping(bytes32 => uint256)) public sharesOf;
    mapping(address => mapping(bytes32 => uint256)) public fullDebtOf;
    mapping(address => mapping(bytes32 => uint256)) public coveredDebtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalUnits;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    /// @dev Cut on interest at each trade for a given obligation id.
    mapping(bytes32 id => uint256) public tradingFee;
    address public tradingFeeRecipient;

    /// @dev Contract owner for administrative functions.
    address public owner;

    /// @dev Address that can set trading fees.
    address public feeSetter;

    /// CONSTRUCTOR ///

    constructor() {
        owner = msg.sender;
    }

    /// ADMIN FUNCTIONS ///

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "Only owner");
        owner = newOwner;
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == owner, "Only owner");
        feeSetter = newFeeSetter;
    }

    function setTradingFee(bytes32 id, uint256 fee) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(fee <= 1e18, "Fee too high");
        tradingFee[id] = fee;
    }

    function setTradingFeeRecipient(address recipient) external {
        require(msg.sender == owner, "Only owner");
        tradingFeeRecipient = recipient;
    }

    /// ENTRY-POINTS ///

    /// @dev Returns buyerAssets, sellerAssets, obligationUnits, obligationShares.
    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev Neither the taker nor the maker can pass from having obligation shares to having debt in one take.
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
        address takerCallbackAddress,
        bytes memory takerCallbackData
    ) public returns (uint256, uint256, uint256, uint256) {
        bytes32 id = _id(offer.obligation);
        require(
            UtilsLib.atMostOneNonZero(buyerAssets, sellerAssets, obligationUnits, obligationShares),
            "inconsistent input"
        );
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(offer.obligation.maturity >= block.timestamp, "maturity");
        require(offer.obligation.chainId == block.chainid, "chain id mismatch");
        require(offer.start < offer.expiry || offer.expiryPrice == offer.startPrice, "inconsistent prices");
        require(offer.maker != taker, "buyer and seller cannot be the same");
        require(_signer(root, sig) == offer.maker, "invalid signature");
        require(MathLib.isLeaf(root, keccak256(abi.encode(offer)), proof), "invalid proof");

        (
            address buyer,
            address buyerCallbackAddress,
            bytes memory buyerCallbackData,
            address seller,
            address sellerCallbackAddress,
            bytes memory sellerCallbackData
        ) = offer.buy
            ? (offer.maker, offer.callbackAddress, offer.callbackData, taker, takerCallbackAddress, takerCallbackData)
            : (taker, takerCallbackAddress, takerCallbackData, offer.maker, offer.callbackAddress, offer.callbackData);

        uint256 offerPrice = offer.expiry != offer.start
            ? offer.startPrice + (offer.expiryPrice - offer.startPrice) * (block.timestamp - offer.start)
                / (offer.expiry - offer.start)
            : offer.startPrice;
        require(offerPrice <= 1e18, "price too high");

        uint256 _tradingFee = tradingFee[id];
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice.mulDivDown(WAD - _tradingFee, WAD) + _tradingFee;
        uint256 sellerPrice = offer.buy ? (offerPrice - _tradingFee).mulDivDown(WAD, WAD - _tradingFee) : offerPrice;

        if (buyerAssets > 0) {
            obligationUnits = buyerAssets.mulDivDown(1e18, buyerPrice);
            sellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else if (sellerAssets > 0) {
            obligationUnits = sellerAssets.mulDivDown(1e18, sellerPrice);
            buyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else if (obligationUnits > 0) {
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, 1e18);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, 1e18);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else {
            obligationUnits = obligationShares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, 1e18);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, 1e18);
        }

        require(
            (consumed[offer.maker][offer.nonce] += (offer.buy ? buyerAssets : sellerAssets)) <= offer.assets, "consumed"
        );

        if (fullDebtOf[buyer][id] == 0 && sharesOf[seller][id] == 0) {
            sharesOf[buyer][id] += obligationShares;
            fullDebtOf[seller][id] += obligationUnits;
            totalShares[id] += obligationShares;
            totalUnits[id] += obligationUnits;
        } else if (fullDebtOf[buyer][id] == 0 && sharesOf[seller][id] > 0) {
            sharesOf[buyer][id] += obligationShares;
            sharesOf[seller][id] -= obligationShares;
        } else if (fullDebtOf[buyer][id] > 0 && sharesOf[seller][id] == 0) {
            fullDebtOf[buyer][id] -= obligationUnits;
            fullDebtOf[seller][id] += obligationUnits;
        } else {
            fullDebtOf[buyer][id] -= obligationUnits;
            sharesOf[seller][id] -= obligationShares;
            totalShares[id] -= obligationShares;
            totalUnits[id] -= obligationUnits;
        }

        if (buyerCallbackAddress != address(0)) {
            ICallbacks(buyerCallbackAddress).onTake(offer.obligation, buyer, buyerAssets, buyerCallbackData);
        }

        SafeTransferLib.safeTransferFrom(
            offer.obligation.loanToken, buyer, tradingFeeRecipient, buyerAssets - sellerAssets
        );
        SafeTransferLib.safeTransferFrom(offer.obligation.loanToken, buyer, seller, sellerAssets);

        if (sellerCallbackAddress != address(0)) {
            ICallbacks(sellerCallbackAddress).onTake(offer.obligation, seller, sellerAssets, sellerCallbackData);
        }

        require(_isHealthy(offer.obligation, seller), "Seller is unhealthy");

        return (buyerAssets, sellerAssets, obligationUnits, obligationShares);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares, address onBehalf)
        external
    {
        require(UtilsLib.atMostOneNonZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = _id(obligation);

        if (obligationUnits > 0) shares = obligationUnits.mulDivUp(totalShares[id] + 1, totalUnits[id] + 1);
        else obligationUnits = shares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);

        if (sharesOf[onBehalf][id] > 0) {
            require(obligation.maturity < block.timestamp, "obligation maturity");
            sharesOf[onBehalf][id] -= shares;
            totalShares[id] -= shares;
            totalUnits[id] -= obligationUnits;
        } else {
            coveredDebtOf[onBehalf][id] -= obligationUnits;
            if (obligation.maturity < block.timestamp) require(debtOf(onBehalf, id) == 0, "no debt");
            else require(_isHealthy(obligation, onBehalf), "Unhealthy borrower");
        }
        withdrawable[id] -= obligationUnits;

        SafeTransferLib.safeTransfer(obligation.loanToken, msg.sender, obligationUnits);
    }

    function repay(Obligation memory obligation, uint256 assets, address onBehalf) external {
        bytes32 id = _id(obligation);
        coveredDebtOf[onBehalf][id] += assets;
        withdrawable[id] += assets;
        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), assets);
    }

    function supplyCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        collateralOf[onBehalf][_id(obligation)][collateral] += assets;
        SafeTransferLib.safeTransferFrom(collateral, msg.sender, address(this), assets);
    }

    function withdrawCollateral(Obligation memory obligation, address collateral, uint256 assets, address onBehalf)
        external
    {
        collateralOf[onBehalf][_id(obligation)][collateral] -= assets;

        require(_isHealthy(obligation, onBehalf), "Unhealthy borrower");

        SafeTransferLib.safeTransfer(collateral, msg.sender, assets);
    }

    /// @notice Execute the given collection of `seizures` on the given `obligation` of the given `borrower`.
    /// @dev On each seizure either `repaid` or `seized` should be equal to zero.
    /// @dev Covered debt cannot be liquidated.
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
        bytes32 id = _id(obligation);
        uint256[] memory prices = new uint256[](obligation.collaterals.length);

        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            prices[i] = IOracle(obligation.collaterals[i].oracle).price();
            uint256 collateralAmount = collateralOf[borrower][id][obligation.collaterals[i].token];
            maxDebt += collateralAmount.mulDivDown(prices[i], ORACLE_PRICE_SCALE)
                .mulDivDown(obligation.collaterals[i].lltv, 1e18);
            repayableDebt += collateralAmount.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR)
                .mulDivUp(prices[i], ORACLE_PRICE_SCALE);
        }

        uint256 originalDebt = debtOf(borrower, id);
        require(originalDebt > maxDebt, "position is healthy");

        uint256 badDebt = originalDebt.zeroFloorSub(repayableDebt);
        if (badDebt > 0) {
            fullDebtOf[borrower][id] -= badDebt;
            totalUnits[id] -= badDebt;
        }

        uint256 totalRepaid;

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            require(UtilsLib.atMostOneNonZero(seizure.repaid, seizure.seized), "INCONSISTENT_INPUT");

            if (seizure.seized > 0) {
                seizure.repaid = seizure.seized.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR)
                    .mulDivUp(prices[seizure.collateralIndex], ORACLE_PRICE_SCALE);
            } else {
                seizure.seized = seizure.repaid.mulDivDown(ORACLE_PRICE_SCALE, prices[seizure.collateralIndex])
                    .mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18);
            }

            totalRepaid += seizure.repaid;
            address collateralToken = obligation.collaterals[seizure.collateralIndex].token;
            collateralOf[borrower][id][collateralToken] -= seizure.seized;
        }

        withdrawable[id] += totalRepaid;
        coveredDebtOf[borrower][id] += totalRepaid;

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

    /// @notice The debt of the borrower excluding the covered amount.
    function debtOf(address borrower, bytes32 id) public view returns (uint256) {
        return MathLib.zeroFloorSub(fullDebtOf[borrower][id], coveredDebtOf[borrower][id]);
    }

    /// INTERNAL ///

    function _id(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function _signer(bytes32 root, Signature memory signature) internal pure returns (address) {
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", root));
        address tentativeSigner = ecrecover(messageHash, signature.v, signature.r, signature.s);
        require(tentativeSigner != address(0), "invalid signature");
        return tentativeSigner;
    }

    function _isHealthy(Obligation memory obligation, address borrower) internal view returns (bool) {
        bytes32 id = _id(obligation);
        uint256 debt = debtOf(borrower, id);
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            address previousCollateralToken;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                address currentCollateralToken = obligation.collaterals[i].token;
                require(currentCollateralToken > previousCollateralToken, "collaterals not sorted");
                uint256 price = IOracle(obligation.collaterals[i].oracle).price();
                maxDebt += collateralOf[borrower][id][currentCollateralToken].mulDivDown(price, ORACLE_PRICE_SCALE)
                    .mulDivDown(obligation.collaterals[i].lltv, 1e18);
                previousCollateralToken = currentCollateralToken;
            }

            return debt <= maxDebt;
        }
    }
}
