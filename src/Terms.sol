// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/ICallbacks.sol";
import "./libraries/TransientLib.sol";

contract Terms is ITerms {
    using MathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 offerStart,uint256 offerExpiry,uint256 rate,uint256 nonce)"
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
    function take(
        Term memory term,
        uint256 assets,
        address onBehalf,
        Offer memory offer,
        Signature memory sig,
        address callbackAddress,
        bytes memory callbackData
    ) public {
        require(block.timestamp >= offer.offerStart, "offer not started");
        require(block.timestamp <= offer.offerExpiry, "offer expired");
        require(term.maturity >= block.timestamp, "bond maturity");
        _checkSignature(offer, sig);
        _checkOffer(term, offer);

        uint256 bonds = assets * (1e18 + (term.maturity - block.timestamp) * offer.rate) / 1e18;

        require((consumed[offer.offering][offer.nonce] += assets) <= offer.assets, "consumed");

        (
            address buyer,
            address buyerCallbackAddress,
            bytes memory buyerCallbackData,
            address seller,
            address sellerCallbackAddress,
            bytes memory sellerCallbackData
        ) = offer.buy
            ? (offer.offering, offer.callbackAddress, offer.callbackData, onBehalf, callbackAddress, callbackData)
            : (onBehalf, callbackAddress, callbackData, offer.offering, offer.callbackAddress, offer.callbackData);

        bytes32 id = _id(term);

        {
            uint256 repaid = UtilsLib.min(debtOf[buyer][id], bonds);
            uint256 bought = bonds - repaid;
            uint256 boughtShares = bought.mulDivDown(totalShares[id] + 1, totalBonds[id] + 1);
            uint256 withdrawn =
                UtilsLib.min(bondSharesOf[seller][id].mulDivDown(totalBonds[id] + 1, totalShares[id] + 1), bonds);
            uint256 withdrawnShares = withdrawn.mulDivUp(totalShares[id] + 1, totalBonds[id] + 1);

            debtOf[buyer][id] -= repaid;
            bondSharesOf[buyer][id] += boughtShares;
            bondSharesOf[seller][id] -= withdrawnShares;
            debtOf[seller][id] += bonds - withdrawn;

            totalShares[id] += boughtShares;
            totalShares[id] -= withdrawnShares;
            totalBonds[id] += bought;
            totalBonds[id] -= withdrawn;
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

    /// @notice Liquidates the given `borrower` on the given `term`.
    /// @param term The term of the bond.
    /// @param collateralIndex The collateral to seize.
    /// @param repaidBonds The amount of debt to repay.
    /// @param seizedAssets The amount of assets to seize.
    /// @param borrower The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return The actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(
        Term memory term,
        uint256 collateralIndex,
        uint256 repaidBonds,
        uint256 seizedAssets,
        address borrower,
        bytes calldata data
    ) external returns (uint256, uint256) {
        require(UtilsLib.atLeastOneZero(repaidBonds, seizedAssets), "INCONSISTENT_INPUT");
        bytes32 id = _id(term);

        if (!TransientLib.getMapping(borrower)) {
            uint256 maxDebt;
            uint256 repayableDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
                repayableDebt += collateralQuoted.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
            }
            require(debtOf[borrower][id] > maxDebt, "position is healthy");
            TransientLib.setMapping(borrower, true);

            if (repayableDebt < debtOf[borrower][id]) {
                uint256 badDebt = debtOf[borrower][id] - repayableDebt;
                debtOf[borrower][id] -= badDebt;
                totalBonds[id] -= badDebt;
            }
        }

        uint256 collateralPrice = IOracle(term.collaterals[collateralIndex].oracle).price();

        if (seizedAssets > 0) {
            repaidBonds =
                seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE).mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
        } else if (repaidBonds > 0) {
            seizedAssets = repaidBonds.mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18).mulDivDown(
                ORACLE_PRICE_SCALE, collateralPrice
            );
        }

        collateralOf[borrower][id][term.collaterals[collateralIndex].token] -= seizedAssets;
        debtOf[borrower][id] -= repaidBonds;
        withdrawable[id] += repaidBonds;

        SafeTransferLib.safeTransfer(term.collaterals[collateralIndex].token, msg.sender, seizedAssets);
        if (data.length > 0) ICallbacks(msg.sender).onLiquidate(repaidBonds, seizedAssets, borrower, msg.sender, data);
        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), repaidBonds);
        return (repaidBonds, seizedAssets);
    }

    /// INTERNAL ///

    function _id(Term memory term) internal pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function _checkOffer(Term memory term, Offer memory offer) internal pure {
        require(offer.loanToken == term.loanToken, "Loan tokens do not match");
        require(offer.maturity == term.maturity, "Maturities do not match");

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

    function _checkSignature(Offer memory offer, Signature memory signature) internal view {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && offer.offering == signatory, "Invalid signature");
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
