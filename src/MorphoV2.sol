// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {
    WAD,
    ORACLE_PRICE_SCALE,
    DOMAIN_TYPEHASH,
    AUTHORIZATION_TYPEHASH,
    MAX_LIF,
    TIME_TO_MAX_LIF
} from "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {
    IMorphoV2,
    Obligation,
    Offer,
    Signature,
    Seizure,
    Authorization,
    TradingFeeParams,
    Proof
} from "./interfaces/IMorphoV2.sol";
import {ICallbacks, IFlashLoanCallback} from "./interfaces/ICallbacks.sol";

/// OBLIGATIONS
/// @dev Obligations' collaterals must be sorted by token address.
contract MorphoV2 is IMorphoV2 {
    using MathLib for uint256;

    /// STORAGE ///

    mapping(address => mapping(bytes32 => uint256)) public sharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalUnits;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    mapping(address => mapping(address => bool)) public authorized;
    mapping(address => uint256) public authorizationNonce;
    mapping(address => mapping(bytes32 => bool)) public ratified;

    /// @dev Groups are useful to have a global offered amount shared accross multiple offers ("OCO").
    /// @dev To work as expected, all offers in a same group should have the same assets, obligationUnits,
    /// obligationShares and loan token.
    mapping(address user => mapping(bytes32 group => uint256)) public consumed;

    /// @dev Offers should have the current session to be valid.
    /// @dev The session can be shuffled by the user to cancel all current offers easily and efficiently.
    mapping(address user => bytes32) public session;

    /// @dev Trading fee parameters for a given obligation id.
    mapping(bytes32 id => TradingFeeParams) public tradingFeeParams;
    address public tradingFeeRecipient;

    /// @dev Contract owner for administrative functions.
    address public owner;

    /// @dev Address that can set trading fees.
    address public feeSetter;

    /// CONSTRUCTOR ///

    constructor() {
        owner = msg.sender;
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
    }

    function setFeeSetter(address newFeeSetter) external {
        require(msg.sender == owner, "Only owner");
        feeSetter = newFeeSetter;
    }

    function setTradingFee(bytes32 id, uint256 tradingFee, uint256 interestCutLimit) external {
        require(msg.sender == feeSetter, "Only feeSetter");
        require(tradingFee <= type(uint128).max, "Trading fee too high");
        require(interestCutLimit < WAD, "Interest cut limit too high");
        // Safe cast because values are below type(uint128).max.
        tradingFeeParams[id] =
            TradingFeeParams({tradingFee: uint128(tradingFee), interestCutLimit: uint128(interestCutLimit)});
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
    /// @dev Neither the taker nor the maker can pass from having shares to having debt in one take.
    function take(
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        Offer memory offer,
        Proof memory proof,
        Signature memory sig,
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
        require(offer.obligation.chainId == block.chainid, "chain id mismatch");
        require(offer.start < offer.expiry || offer.expiryPrice == offer.startPrice, "inconsistent prices");
        require(offer.maker != taker, "buyer and seller cannot be the same");
        require(offer.session == session[offer.maker], "invalid session");
        require(msg.sender == taker || authorized[taker][msg.sender], "order not authorized");
        require(MathLib.isLeaf(proof.root, keccak256(abi.encode(offer)), proof.path), "invalid proof");

        if (sig.v != 0) {
            address tentativeSigner = MathLib.messageSigner(proof.root, sig.v, sig.r, sig.s);
            require(tentativeSigner != address(0), "invalid signature");
            if (offer.ratifier != address(0)) {
                require(
                    (offer.maker == offer.ratifier || authorized[offer.maker][offer.ratifier])
                        && ICallbacks(offer.ratifier).onRatify(offer, tentativeSigner),
                    "offer ratification failed"
                );
            } else {
                require(tentativeSigner == offer.maker, "invalid signer");
            }
        } else {
            require(ratified[offer.maker][proof.root], "offer not ratified");
        }
        bytes32 id = _id(offer.obligation);

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

        uint256 offerPrice = offer.expiry != offer.start
            ? offer.startPrice + (offer.expiryPrice - offer.startPrice) * (block.timestamp - offer.start)
                / (offer.expiry - offer.start)
            : offer.startPrice;
        require(offerPrice <= WAD, "price too high");

        TradingFeeParams memory _tradingFeeParams = tradingFeeParams[id];
        uint256 buyerPrice;
        uint256 sellerPrice;
        if (offer.buy) {
            buyerPrice = offerPrice;
            sellerPrice = UtilsLib.max(
                (buyerPrice.zeroFloorSub(_tradingFeeParams.interestCutLimit))
                .mulDivDown(WAD, WAD - _tradingFeeParams.interestCutLimit),
                buyerPrice.mulDivDown(WAD, WAD + _tradingFeeParams.tradingFee)
            );
        } else {
            sellerPrice = offerPrice;
            buyerPrice = UtilsLib.min(
                sellerPrice.mulDivDown(WAD - _tradingFeeParams.interestCutLimit, WAD)
                    + _tradingFeeParams.interestCutLimit,
                sellerPrice.mulDivDown(WAD + _tradingFeeParams.tradingFee, WAD)
            );
        }

        if (buyerAssets > 0) {
            obligationUnits = buyerAssets.mulDivDown(WAD, buyerPrice);
            sellerAssets = buyerAssets.mulDivDown(sellerPrice, buyerPrice);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else if (sellerAssets > 0) {
            obligationUnits = sellerAssets.mulDivDown(WAD, sellerPrice);
            buyerAssets = sellerAssets.mulDivDown(buyerPrice, sellerPrice);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else if (obligationUnits > 0) {
            buyerAssets = obligationUnits.mulDivDown(buyerPrice, WAD);
            sellerAssets = obligationUnits.mulDivDown(sellerPrice, WAD);
            obligationShares = obligationUnits.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        } else {
            obligationUnits = obligationShares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);
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

        if (debtOf[buyer][id] == 0 && sharesOf[seller][id] == 0) {
            // Lender enters + borrower enters.
            sharesOf[buyer][id] += obligationShares;
            debtOf[seller][id] += obligationUnits;
            totalShares[id] += obligationShares;
            totalUnits[id] += obligationUnits;
        } else if (debtOf[buyer][id] == 0 && sharesOf[seller][id] > 0) {
            // Lender enters + lender exits.
            sharesOf[buyer][id] += obligationShares;
            sharesOf[seller][id] -= obligationShares;
        } else if (debtOf[buyer][id] > 0 && sharesOf[seller][id] == 0) {
            // Borrower exits + borrower enters.
            debtOf[buyer][id] -= obligationUnits;
            debtOf[seller][id] += obligationUnits;
        } else {
            // Borrower exits + lender exits.
            debtOf[buyer][id] -= obligationUnits;
            sharesOf[seller][id] -= obligationShares;
            totalShares[id] -= obligationShares;
            totalUnits[id] -= obligationUnits;
        }

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

        require(_isHealthy(offer.obligation, seller), "Seller is unhealthy");

        return (buyerAssets, sellerAssets, obligationUnits, obligationShares);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares, address onBehalf)
        external
        returns (uint256, uint256)
    {
        require(msg.sender == onBehalf || authorized[onBehalf][msg.sender], "withdraw not authorized");
        require(UtilsLib.atMostOneNonZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = _id(obligation);

        if (obligationUnits > 0) shares = obligationUnits.mulDivUp(totalShares[id] + 1, totalUnits[id] + 1);
        else obligationUnits = shares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);

        sharesOf[onBehalf][id] -= shares;
        withdrawable[id] -= obligationUnits;

        totalShares[id] -= shares;
        totalUnits[id] -= obligationUnits;

        SafeTransferLib.safeTransfer(obligation.loanToken, msg.sender, obligationUnits);

        return (obligationUnits, shares);
    }

    function repay(Obligation memory obligation, uint256 obligationUnits, address onBehalf) external {
        bytes32 id = _id(obligation);

        debtOf[onBehalf][id] -= obligationUnits;
        withdrawable[id] += obligationUnits;

        SafeTransferLib.safeTransferFrom(obligation.loanToken, msg.sender, address(this), obligationUnits);
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
        require(msg.sender == onBehalf || authorized[onBehalf][msg.sender], "withdrawCollateral not authorized");
        collateralOf[onBehalf][_id(obligation)][collateral] -= assets;

        require(_isHealthy(obligation, onBehalf), "Unhealthy borrower");

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
        bytes32 id = _id(obligation);
        uint256[] memory prices = new uint256[](obligation.collaterals.length);

        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            prices[i] = IOracle(obligation.collaterals[i].oracle).price();
            uint256 collateralAmount = collateralOf[borrower][id][obligation.collaterals[i].token];
            maxDebt += collateralAmount.mulDivDown(prices[i], ORACLE_PRICE_SCALE)
                .mulDivDown(obligation.collaterals[i].lltv, WAD);
            repayableDebt += collateralAmount.mulDivUp(WAD, MAX_LIF).mulDivUp(prices[i], ORACLE_PRICE_SCALE);
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

    function setRatified(address onBehalf, bytes32 root, bool newRatified) external {
        require(msg.sender == onBehalf || authorized[onBehalf][msg.sender], "ratification not authorized");
        ratified[onBehalf][root] = newRatified;
    }

    function setAuthorized(address authorizee, bool newAuthorized) external {
        authorized[msg.sender][authorizee] = newAuthorized;
    }

    function setAuthorizedWithSig(Authorization memory authorization, Signature calldata signature) external {
        /// Do not check whether authorization is already set because the nonce increment is a desired side effect.
        require(block.timestamp <= authorization.deadline, "expired");
        require(authorization.nonce == authorizationNonce[authorization.authorizer]++, "invalid nonce");

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        require(signatory != address(0) && signatory == authorization.authorizer, "invalid signature");

        authorized[authorization.authorizer][authorization.authorizee] = authorization.isAuthorized;
    }

    function consume(bytes32 group, uint256 amount) external {
        consumed[msg.sender][group] += amount;
    }

    /// @dev TODO: is it safe enough?
    function shuffleSession() external {
        session[msg.sender] = keccak256(abi.encode(session[msg.sender], blockhash(block.number - 1)));
    }

    function flashLoan(address token, uint256 amount, address callback, bytes calldata data) external {
        SafeTransferLib.safeTransfer(token, msg.sender, amount);

        IFlashLoanCallback(callback).onFlashLoan(token, amount, data);

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    /// INTERNAL ///

    function _id(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function _isHealthy(Obligation memory obligation, address borrower) internal view returns (bool) {
        bytes32 id = _id(obligation);
        uint256 debt = debtOf[borrower][id];
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
                    .mulDivDown(obligation.collaterals[i].lltv, WAD);
                previousCollateralToken = currentCollateralToken;
            }

            return debt <= maxDebt;
        }
    }
}
