// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/ICallbacks.sol";
import "./interfaces/IValidation.sol";

contract Terms is ITerms {
    using MathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 rate,uint256 nonce)"
    );
    uint256 public constant ORACLE_PRICE_SCALE = 1e36;
    uint256 public constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// STORAGE ///

    mapping(address user => mapping(bytes32 termId => uint256)) public bondSharesOf;
    mapping(address user => mapping(bytes32 termId => uint256)) public debtOf;
    mapping(bytes32 termId => uint256) public withdrawable;
    mapping(bytes32 termId => uint256) public totalBonds;
    mapping(bytes32 termId => uint256) public totalShares;
    mapping(address user => mapping(bytes32 termId => mapping(address collateralToken => uint256))) public collateralOf;

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    mapping(address user => mapping(bytes offer => bool)) public ratified;

    /// ENTRY-POINTS ///

    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    function take(
        Term memory term,
        Offer memory offer,
        Signature memory sig,
        uint256 assets,
        uint256 bonds,
        address onBehalf,
        address callbackAddress,
        bytes memory callbackData
    ) public {
        require(term.maturity >= block.timestamp, "bond maturity");
        require(block.timestamp >= offer.offerStart, "offer not started");
        require(block.timestamp <= offer.offerExpiry, "offer expired");
        require(IValidation(offer.validation).validate(term, assets, offer.offerData), "invalid offer");
        require(_canUseOffer(offer, sig), "invalid offer");

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

        require((consumed[offer.offering][offer.nonce] += assets) <= offer.assets, "consumed");

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

        SafeTransferLib.safeTransferFrom(term.loanToken, buyer, seller, assets);

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

    struct Vars {
        uint256 maxDebt;
        uint256 repayableDebt;
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrower`.
    /// @dev On each seizure either `repaidAmounts` or `seizedAssets` should be equal to zero.
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
        require(seizures.length == term.collaterals.length, "should have all collats");

        Vars memory vars;
        bytes32 id = _id(term);

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            uint256 price = IOracle(term.collaterals[i].oracle).price();
            uint256 collateralQuoted =
                collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
            vars.maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
            vars.repayableDebt += collateralQuoted.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
        }
        require(debtOf[borrower][id] > vars.maxDebt, "position is healthy");

        uint256 totalRepaid;

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            if (seizures[i].repaidBonds + seizures[i].seizedAssets > 0) {
                require(
                    UtilsLib.exactlyOneZero(seizures[i].repaidBonds, seizures[i].seizedAssets), "INCONSISTENT_INPUT"
                );

                uint256 collateralPrice = IOracle(term.collaterals[i].oracle).price();

                if (seizures[i].seizedAssets > 0) {
                    seizures[i].repaidBonds = seizures[i].seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE)
                        .mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
                } else {
                    seizures[i].seizedAssets = seizures[i].repaidBonds.mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18)
                        .mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
                }

                totalRepaid += seizures[i].repaidBonds;
                collateralOf[borrower][id][term.collaterals[i].token] -= seizures[i].seizedAssets;

                SafeTransferLib.safeTransfer(term.collaterals[i].token, msg.sender, seizures[i].seizedAssets);
            }
        }

        uint256 originalDebt = debtOf[borrower][id];
        debtOf[borrower][id] -= totalRepaid;

        // Realize bad debt
        if (vars.repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original
            // debt minus the theoretical repayable debt.
            uint256 badDebt = UtilsLib.min(debtOf[borrower][id], originalDebt - vars.repayableDebt);
            debtOf[borrower][id] -= badDebt;
            totalBonds[id] -= badDebt;
        }

        withdrawable[id] += totalRepaid;

        if (data.length > 0) ICallbacks(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
    }

    function setRatified(Offer memory offer, bool newRatified) external {
        ratified[msg.sender][abi.encode(offer)] = newRatified;
    }

    /// INTERNAL ///

    function _id(Term memory term) internal pure returns (bytes32) {
        return keccak256(abi.encode(term));
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

    function _canUseOffer(Offer memory offer, Signature memory sig) internal view returns (bool) {
        if (sig.v == 0) {
            return ratified[offer.offering][abi.encode(offer)];
        } else {
            bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
            bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
            bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
            address signatory = ecrecover(digest, sig.v, sig.r, sig.s);
            return signatory != address(0) && offer.offering == signatory;
        }
    }
}
