// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/IMorphoLiquidationCallback.sol";

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
    mapping(address => mapping(bytes32 => uint256)) public debtSharesOf;
    mapping(address => mapping(bytes32 => uint256)) public coverSharesOf;
    mapping(bytes32 => uint256) public totalBonds;
    mapping(bytes32 => uint256) public totalBondShares;
    mapping(bytes32 => uint256) public totalDebt;
    mapping(bytes32 => uint256) public totalDebtShares;
    mapping(bytes32 => uint256) public totalCover;
    mapping(bytes32 => uint256) public totalCoverShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    /// ENTRY-POINTS ///

    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    function take(Term memory term, uint256 assets, address onBehalf, Offer memory offer, Signature memory sig)
        public
    {
        require(block.timestamp >= offer.offerStart, "offer not started");
        require(block.timestamp <= offer.offerExpiry, "offer expired");
        require(term.maturity >= block.timestamp, "bond maturity");
        _checkSignature(offer, sig);
        _checkOffer(term, offer);

        uint256 bonds = assets * (1e18 + (term.maturity - block.timestamp) * offer.rate) / 1e18;

        require((consumed[offer.offering][offer.nonce] += assets) <= offer.assets, "consumed");

        (address buyer, address seller) = offer.buy ? (offer.offering, onBehalf) : (onBehalf, offer.offering);
        bytes32 id = _id(term);

        {
            uint256 repaid =
                UtilsLib.min(debtSharesOf[buyer][id].mulDivUp(totalDebt[id] + 1, totalDebtShares[id] + 1), bonds);
            uint256 repaidShares = repaid.mulDivDown(totalDebtShares[id] + 1, totalDebt[id] + 1);
            uint256 bought = bonds - repaid;
            uint256 boughtShares = bought.mulDivDown(totalBondShares[id] + 1, totalBonds[id] + 1);
            uint256 withdrawn =
                UtilsLib.min(bondSharesOf[seller][id].mulDivDown(totalBonds[id] + 1, totalBondShares[id] + 1), bonds);
            uint256 withdrawnShares = withdrawn.mulDivUp(totalBondShares[id] + 1, totalBonds[id] + 1);
            uint256 borrowed = bonds - withdrawn;
            uint256 borrowedShares = borrowed.mulDivUp(totalDebtShares[id] + 1, totalDebt[id] + 1);

            debtSharesOf[buyer][id] -= repaidShares;
            bondSharesOf[buyer][id] += boughtShares;
            bondSharesOf[seller][id] -= withdrawnShares;
            debtSharesOf[seller][id] += borrowedShares;

            totalBondShares[id] += boughtShares;
            totalBondShares[id] -= withdrawnShares;
            totalBonds[id] += bought;
            totalBonds[id] -= withdrawn;
            totalDebtShares[id] += borrowedShares;
            totalDebtShares[id] -= repaidShares;
            totalDebt[id] += borrowed;
            totalDebt[id] -= repaid;

            require(_isHealthy(term, seller), "Seller is unhealthy");
        }

        SafeTransferLib.safeTransferFrom(offer.loanToken, buyer, seller, assets);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 bonds, uint256 bondShares, address onBehalf) external {
        require(term.maturity < block.timestamp, "bond maturity");
        require(UtilsLib.exactlyOneZero(bonds, bondShares), "INCONSISTENT_INPUT");
        bytes32 id = _id(term);

        if (bonds > 0) bondShares = bonds.mulDivUp(totalBondShares[id] + 1, totalBonds[id] + 1);
        else bonds = bondShares.mulDivDown(totalBonds[id] + 1, totalBondShares[id] + 1);

        bondSharesOf[onBehalf][id] -= bondShares;

        totalBondShares[id] -= bondShares;
        totalBonds[id] -= bonds;
        totalCover[id] -= bonds;

        SafeTransferLib.safeTransfer(term.loanToken, msg.sender, bonds);
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

    function supplyCover(Term memory term, uint256 assets, address onBehalf) external {
        bytes32 id = _id(term);
        uint256 coverShares = assets.mulDivDown(totalCoverShares[id] + 1, totalCover[id] + 1);
        coverSharesOf[onBehalf][id] += coverShares;
        totalCoverShares[id] += coverShares;
        totalCover[id] += assets;
        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), assets);
    }

    function withdrawCover(Term memory term, uint256 assets, address onBehalf) external {
        bytes32 id = _id(term);
        uint256 coverShares = assets.mulDivUp(totalCoverShares[id] + 1, totalCover[id] + 1);
        coverSharesOf[onBehalf][id] -= coverShares;
        totalCoverShares[id] -= coverShares;
        totalCover[id] -= assets;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        SafeTransferLib.safeTransfer(term.loanToken, msg.sender, assets);
    }

    struct Vars {
        uint256 maxDebt;
        uint256 repayableDebt;
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrower`.
    /// @dev On each seizure either `repaidAmounts` or `seizedAssets` should be equal to zero.
    /// @dev Covered debt cannot be liquidated.
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
        require(debtOf(borrower, id) > vars.maxDebt, "position is healthy");

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

        uint256 originalDebt = debtOf(borrower, id);
        uint256 coverShares = totalRepaid.mulDivDown(totalCoverShares[id] + 1, totalCover[id] + 1);
        coverSharesOf[borrower][id] += coverShares;
        totalCoverShares[id] += coverShares;
        totalCover[id] += totalRepaid;

        // Realize bad debt
        if (vars.repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original
            // debt minus the theoretical repayable debt.
            uint256 badDebt = UtilsLib.min(debtOf(borrower, id), originalDebt - vars.repayableDebt);
            debtSharesOf[borrower][id] -= badDebt.mulDivUp(totalDebtShares[id] + 1, totalDebt[id] + 1);
            totalBonds[id] -= badDebt;
        }

        if (data.length > 0) IMorphoLiquidationCallback(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
    }

    /// VIEWS ///

    /// @notice The debt of the borrower excluding the covered amount.
    function debtOf(address borrower, bytes32 id) public view returns (uint256) {
        uint256 debt = debtSharesOf[borrower][id].mulDivUp(totalDebt[id] + 1, totalDebtShares[id] + 1);
        uint256 cover = coverSharesOf[borrower][id].mulDivDown(totalCover[id] + 1, totalCoverShares[id] + 1);

        return MathLib.zeroFloorSub(debt, cover);
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
        uint256 debt = debtOf(borrower, id);
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
