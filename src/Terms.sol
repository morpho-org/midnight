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

    struct User {
        uint256 debt;
        uint256 bondShares;
        mapping (address collateralAddress => uint256) collateral;
    }

    struct Loan {
        uint256 withdrawable;
        uint256 totalBonds;
        uint256 totalShares;
        mapping(address userAddress => User) users;
    }

    mapping(bytes32 termId => Loan) public loans;

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


        (address buyerAddress, address sellerAddress) = offer.buy ? (offer.offering, onBehalf) : (onBehalf, offer.offering);
        Loan storage loan = loans[_id(term)];
        User storage buyer = loan.users[buyerAddress];
        User storage seller = loan.users[sellerAddress];
        {
            uint256 repaid = UtilsLib.min(buyer.debt, bonds);
            uint256 bought = bonds - repaid;
            uint256 boughtShares = bought.mulDivDown(loan.totalShares + 1, loan.totalBonds + 1);
            uint256 withdrawn =
                UtilsLib.min(seller.bondShares.mulDivDown(loan.totalBonds + 1, loan.totalShares + 1), bonds);
            uint256 withdrawnShares = withdrawn.mulDivUp(loan.totalShares + 1, loan.totalBonds + 1);

            buyer.debt -= repaid;
            buyer.bondShares += boughtShares;
            seller.bondShares -= withdrawnShares;
            seller.debt += bonds - withdrawn;

            loan.totalShares += boughtShares;
            loan.totalShares -= withdrawnShares;
            loan.totalBonds += bought;
            loan.totalBonds -= withdrawn;

            require(_isHealthy(term, sellerAddress), "Seller is unhealthy");

        }

        SafeTransferLib.safeTransferFrom(offer.loanToken, buyerAddress, sellerAddress, assets);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 bonds, uint256 shares, address onBehalf) external {
        require(UtilsLib.exactlyOneZero(bonds, shares), "INCONSISTENT_INPUT");
        Loan storage loan = loans[_id(term)];

        if (bonds > 0) shares = bonds.mulDivUp(loan.totalShares + 1, loan.totalBonds + 1);
        else bonds = shares.mulDivDown(loan.totalBonds + 1, loan.totalShares + 1);

        loan.users[onBehalf].bondShares -= shares;
        loan.withdrawable -= bonds;

        loan.totalShares -= shares;
        loan.totalBonds -= bonds;

        SafeTransferLib.safeTransfer(term.loanToken, msg.sender, bonds);
    }

    function repayDebt(Term memory term, uint256 bonds, address onBehalf) external {
        Loan storage loan = loans[_id(term)];

        loan.users[onBehalf].debt -= bonds;
        loan.withdrawable += bonds;

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), bonds);
    }

    function supplyCollateral(Term memory term, address collateralAddress, uint256 assets, address onBehalf) external {
        loans[_id(term)].users[onBehalf].collateral[collateralAddress] += assets;
        SafeTransferLib.safeTransferFrom(collateralAddress, msg.sender, address(this), assets);
    }

    function withdrawCollateral(Term memory term, address collateralAddress, uint256 assets, address onBehalf) external {
        loans[_id(term)].users[onBehalf].collateral[collateralAddress] -= assets;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        SafeTransferLib.safeTransfer(collateralAddress, msg.sender, assets);
    }

    struct Vars {
        uint256 maxDebt;
        uint256 repayableDebt;
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrowerAddress`.
    /// @dev On each seizure either `repaidAmounts` or `seizedAssets` should be equal to zero.
    /// @param term The term of the bond.
    /// @param seizures An array of amounts of debt to repay or assets to seize with the index of the collateral in the
    /// term's collateral assets.
    /// @param borrowerAddress The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return A collection of the actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(Term memory term, Seizure[] memory seizures, address borrowerAddress, bytes calldata data)
        external
        returns (Seizure[] memory)
    {
        require(seizures.length == term.collaterals.length, "should have all collats");

        Vars memory vars;
        Loan storage loan = loans[_id(term)];
        User storage borrower = loan.users[borrowerAddress];

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            uint256 price = IOracle(term.collaterals[i].oracle).price();
            uint256 collateralQuoted =
                borrower.collateral[term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
            vars.maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
            vars.repayableDebt += collateralQuoted.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
        }
        require(borrower.debt > vars.maxDebt, "position is healthy");

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
                borrower.collateral[term.collaterals[i].token] -= seizures[i].seizedAssets;

                SafeTransferLib.safeTransfer(term.collaterals[i].token, msg.sender, seizures[i].seizedAssets);
            }
        }

        uint256 originalDebt = borrower.debt;
        borrower.debt -= totalRepaid;

        // Realize bad debt
        if (vars.repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original
            // debt minus the theoretical repayable debt.
            uint256 badDebt = UtilsLib.min(borrower.debt, originalDebt - vars.repayableDebt);
            borrower.debt -= badDebt;
            loan.totalBonds -= badDebt;
        }

        loan.withdrawable += totalRepaid;

        if (data.length > 0) IMorphoLiquidationCallback(msg.sender).onLiquidate(seizures, borrowerAddress, msg.sender, data);

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
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

    function _isHealthy(Term memory term, address borrowerAddress) internal view returns (bool) {
        User storage borrower = loans[_id(term)].users[borrowerAddress];

        uint256 debt = borrower.debt;
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    borrower.collateral[term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.mulDivDown(term.collaterals[i].lltv, 1e18);
            }

            return debt <= maxDebt;
        }
    }

    // GETTER FUNCTIONS //

    function debtOf(address borrowerAddress, bytes32 termId) external view returns (uint256) {
        return loans[termId].users[borrowerAddress].debt;
    }

    function bondSharesOf(address borrowerAddress, bytes32 termId) external view returns (uint256) {
        return loans[termId].users[borrowerAddress].bondShares;
    }

    function collateralOf(address borrowerAddress, bytes32 termId, address collateral) external view returns (uint256) {
        return loans[termId].users[borrowerAddress].collateral[collateral];
    }

    function withdrawable(bytes32 termId) external view returns (uint256) {
        return loans[termId].withdrawable;
    }

    function totalBonds(bytes32 termId) external view returns (uint256) {
        return loans[termId].totalBonds;
    }

    function totalShares(bytes32 termId) external view returns (uint256) {
        return loans[termId].totalShares;
    }

}
