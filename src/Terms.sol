// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/ICallbacks.sol";

contract Terms is ITerms {
    using MathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 start,uint256 expiry,uint256 startPrice,uint256 expiryPrice,uint256 nonce)"
    );
    uint256 public constant ORACLE_PRICE_SCALE = 1e36;
    uint256 public constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// STORAGE ///

    mapping(address => mapping(bytes32 => uint256)) public bondSharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalBonds;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    /// ENTRY-POINTS ///

    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev "Crossing" is prevented.
    function take(
        Term memory term,
        uint256 assets,
        uint256 bondsUnits,
        uint256 bondsShares,
        address taker,
        Offer memory offer,
        Signature memory sig,
        address takerCallbackAddress,
        bytes memory takerCallbackData
    ) public {
        bytes32 id = _id(term);
        uint256 countNonZero = assets > 0 ? 1 : 0 + (bondsUnits > 0 ? 1 : 0) + (bondsShares > 0 ? 1 : 0);
        require(countNonZero <= 1, "inconsistent input");
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(term.maturity >= block.timestamp, "bond maturity");
        require(offer.loanToken == term.loanToken, "Loan tokens do not match");
        require(offer.maturity == term.maturity, "Maturities do not match");
        require(signatureIsValid(offer, sig), "Invalid signature");
        _checkCollateralInclusion(term, offer);

        (
            address buyer,
            address buyerCallbackAddress,
            bytes memory buyerCallbackData,
            address seller,
            address sellerCallbackAddress,
            bytes memory sellerCallbackData
        ) = offer.buy
            ? (offer.offering, offer.callbackAddress, offer.callbackData, taker, takerCallbackAddress, takerCallbackData)
            : (taker, takerCallbackAddress, takerCallbackData, offer.offering, offer.callbackAddress, offer.callbackData);

        uint256 offerDuration = offer.expiry - offer.start;
        uint256 price = offerDuration > 0
            ? offer.startPrice + (offer.expiryPrice - offer.startPrice) * (block.timestamp - offer.start) / offerDuration
            : offer.startPrice;

        if (assets > 0) {
            bondsUnits = assets.mulDivDown(1e18, price);
            bondsShares = bondsUnits.mulDivDown(totalShares[id] + 1, totalBonds[id] + 1);
        } else if (bondsUnits > 0) {
            assets = bondsUnits.mulDivDown(price, 1e18);
            bondsShares = bondsUnits.mulDivDown(totalShares[id] + 1, totalBonds[id] + 1);
        } else {
            bondsUnits = bondsShares.mulDivDown(totalBonds[id] + 1, totalShares[id] + 1);
            assets = bondsUnits.mulDivDown(price, 1e18);
        }

        require((consumed[offer.offering][offer.nonce] += assets) <= offer.assets, "consumed");

        if (debtOf[buyer][id] == 0) {
            if (bondSharesOf[seller][id] == 0) {
                bondSharesOf[buyer][id] += bondsShares;
                debtOf[seller][id] += bondsUnits;
                totalShares[id] += bondsShares;
                totalBonds[id] += bondsUnits;
            } else {
                bondSharesOf[buyer][id] += bondsShares;
                bondSharesOf[seller][id] -= bondsShares;
            }
        } else {
            if (bondSharesOf[seller][id] == 0) {
                debtOf[buyer][id] -= bondsUnits;
                debtOf[seller][id] += bondsUnits;
            } else {
                debtOf[buyer][id] -= bondsUnits;
                bondSharesOf[seller][id] -= bondsShares;
                totalShares[id] -= bondsShares;
                totalBonds[id] -= bondsUnits;
            }
        }

        if (buyerCallbackAddress != address(0)) {
            ICallbacks(buyerCallbackAddress).onTake(term, buyer, assets, buyerCallbackData);
        }

        SafeTransferLib.safeTransferFrom(offer.loanToken, buyer, seller, assets);

        if (sellerCallbackAddress != address(0)) {
            ICallbacks(sellerCallbackAddress).onTake(term, seller, assets, sellerCallbackData);
        }

        require(_isHealthy(term, seller), "Seller is unhealthy");
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 bonds, uint256 shares, address onBehalf) external {
        require(UtilsLib.exactlyOneZero(bonds, shares), "INCONSISTENT_INPUT");
        bytes32 id = _id(term);

        if (bonds > 0) shares = bonds.mulDivUp(totalShares[id] + 1, totalBonds[id] + 1);
        else bonds = shares.mulDivDown(totalBonds[id] + 1, totalShares[id] + 1);

        bondSharesOf[onBehalf][id] -= shares;
        withdrawable[id] -= bonds;

        totalShares[id] -= shares;
        totalBonds[id] -= bonds;

        SafeTransferLib.safeTransfer(term.loanToken, msg.sender, bonds);
    }

    function repayDebt(Term memory term, uint256 bonds, address onBehalf) external {
        bytes32 id = _id(term);

        debtOf[onBehalf][id] -= bonds;
        withdrawable[id] += bonds;

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), bonds);
    }

    function supplyCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] += assets;
        SafeTransferLib.safeTransferFrom(collateral, msg.sender, address(this), assets);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] -= assets;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        SafeTransferLib.safeTransfer(collateral, msg.sender, assets);
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrower`.
    /// @dev On each seizure either `repaidBonds` or `seizedAssets` should be equal to zero.
    /// @param term The term of the bond.
    /// @param seizures An array of amounts of debt to repay or assets to seize with the index of the collateral in the
    /// term's collateral assets.
    /// @param borrower The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return A collection of the actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(Term memory term, Seizure[] memory seizures, address borrower, bytes calldata data)
        external
        returns (Seizure[] memory)
    {
        uint256 repayableDebt;
        uint256 maxDebt;
        bytes32 id = _id(term);
        uint256[] memory prices = new uint256[](term.collaterals.length);

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            prices[i] = IOracle(term.collaterals[i].oracle).price();
            {
                address collateralToken = term.collaterals[i].token;
                uint256 collateralQuoted =
                    collateralOf[borrower][id][collateralToken].mulDivDown(prices[i], ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
                repayableDebt += collateralQuoted.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
            }
        }

        uint256 originalDebt = debtOf[borrower][id];
        require(originalDebt > maxDebt, "position is healthy");

        uint256 totalRepaid;

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            require(UtilsLib.exactlyOneZero(seizure.repaidBonds, seizure.seizedAssets), "INCONSISTENT_INPUT");

            if (seizure.seizedAssets > 0) {
                seizure.repaidBonds = seizure.seizedAssets.mulDivUp(prices[seizure.collateralIndex], ORACLE_PRICE_SCALE)
                    .mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
            } else {
                seizure.seizedAssets = seizure.repaidBonds.mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18).mulDivDown(
                    ORACLE_PRICE_SCALE, prices[seizure.collateralIndex]
                );
            }

            totalRepaid += seizure.repaidBonds;
            address collateralToken = term.collaterals[seizure.collateralIndex].token;
            collateralOf[borrower][id][collateralToken] -= seizure.seizedAssets;
        }

        // Realize bad debt
        uint256 badDebt;

        if (repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original
            // debt minus the theoretical repayable debt.
            badDebt = UtilsLib.min(originalDebt - totalRepaid, originalDebt - repayableDebt);
            totalBonds[id] -= badDebt;
        }

        withdrawable[id] += totalRepaid;
        debtOf[borrower][id] = originalDebt - totalRepaid - badDebt;

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            SafeTransferLib.safeTransfer(
                term.collaterals[seizure.collateralIndex].token, msg.sender, seizure.seizedAssets
            );
        }

        if (data.length > 0) ICallbacks(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
    }

    /// INTERNAL ///

    function _id(Term memory term) internal pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function _checkCollateralInclusion(Term memory term, Offer memory offer) internal pure {
        Collateral[] memory subset = offer.buy ? term.collaterals : offer.collaterals;
        Collateral[] memory superset = offer.buy ? offer.collaterals : term.collaterals;

        uint256 j = 0;
        for (uint256 i = 0; i < subset.length; i++) {
            // Relies on the fact that the collaterals are sorted.
            // Note that we actually never check that.
            // If they are not, the matching could fail.
            while (superset[j].token != subset[i].token) j++;
            require(superset[j].lltv >= subset[i].lltv, "LLTVs do not match");
            require(subset[i].oracle == superset[j].oracle, "Oracles do not match");
            j++;
        }
    }

    function signatureIsValid(Offer memory offer, Signature memory signature) internal view returns (bool) {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        return signatory != address(0) && offer.offering == signatory;
    }

    function _isHealthy(Term memory term, address borrower) internal view returns (bool) {
        bytes32 id = _id(term);
        uint256 debt = debtOf[borrower][id];
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
            }

            return debt <= maxDebt;
        }
    }
}
