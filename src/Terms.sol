// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/IMorphoLiquidationCallback.sol";
import "forge-std/console.sol";

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

            (uint256 maxDebt,) = health(term, seller);
            require(debtOf[seller][id] <= maxDebt, "Seller is unhealthy");
        }

        SafeTransferLib.safeTransferFrom(offer.loanToken, buyer, seller, assets);
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
        bytes32 id = _id(term);
        collateralOf[onBehalf][id][collateral] -= assets;

        (uint256 maxDebt,) = health(term, onBehalf);
        require(debtOf[onBehalf][id] <= maxDebt, "Unhealthy borrower");

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
        (uint256 maxDebt, uint256 repayableDebt) = health(term, borrower);
        bytes32 id = _id(term);
        uint256 originalDebt = debtOf[borrower][id];
        require(originalDebt > repayableDebt, "position is healthy");

        uint256 totalRepaid;
        Seizure memory seizure;

        for (uint256 i = 0; i < seizures.length; i++) {
            seizure = seizures[i];
            require(UtilsLib.exactlyOneZero(seizure.repaidBonds, seizure.seizedAssets), "INCONSISTENT_INPUT");

            uint256 price = IOracle(term.collaterals[seizure.collateralIndex].oracle).price();

            if (seizure.seizedAssets > 0) {
                seizure.repaidBonds = seizure.seizedAssets.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(
                    1e18, LIQUIDATION_INCENTIVE_FACTOR
                );
            } else {
                seizure.seizedAssets = seizure.repaidBonds.mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18).mulDivDown(
                    ORACLE_PRICE_SCALE, price
                );
            }

            totalRepaid += seizure.repaidBonds;
            address collateralToken = term.collaterals[seizure.collateralIndex].token;
            collateralOf[borrower][id][collateralToken] -= seizure.seizedAssets;
        }

        // Realize bad debt
        uint256 badDebt;

        if (totalRepaid > originalDebt) totalRepaid = originalDebt;
        if (repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original
            // debt minus the theoretical repayable debt.
            badDebt = UtilsLib.min(originalDebt - totalRepaid, originalDebt - repayableDebt);
            totalBonds[id] -= badDebt;
        }

        withdrawable[id] += totalRepaid;
        debtOf[borrower][id] = originalDebt - totalRepaid - badDebt;

        for (uint256 i = 0; i < seizures.length; i++) {
            seizure = seizures[i];
            SafeTransferLib.safeTransfer(
                term.collaterals[seizure.collateralIndex].token, msg.sender, seizure.seizedAssets
            );
        }

        if (data.length > 0) IMorphoLiquidationCallback(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

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

    ///@dev Returns the max debt and the repayable debt.
    function health(Term memory term, address borrower) public view returns (uint256, uint256) {
        bytes32 id = _id(term);
        uint256 totalCollateralValue;
        for (uint256 i = 0; i < term.collaterals.length; i++) {
            uint256 price = IOracle(term.collaterals[i].oracle).price();
            uint256 collateralValue =
                collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
            _health.maxDebt += collateralValue.mulDivDown(term.collaterals[i].lltv, 1e18);
            totalCollateralValue += collateralValue;
        }
        return (maxDebt, totalCollateralValue.mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR));
    }
}
