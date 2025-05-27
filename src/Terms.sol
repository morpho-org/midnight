// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import {MathLib, WAD} from "./libraries/MathLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/IMorphoLiquidationCallback.sol";

contract Terms is ITerms {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 price)"
    );

    uint256 public constant ORACLE_PRICE_SCALE = 1e36;

    /// STORAGE ///

    // Terms.
    mapping(address => mapping(bytes32 => uint256)) public bondSharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalAssets;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    // Offers.
    mapping(bytes => uint256) public consumed;

    /// ENTRY-POINTS ///

    /// @dev This function is used for both primary and secondary markets.
    function MATCH(Offer memory buyOffer, Signature memory buySig, Offer memory sellOffer, Signature memory sellSig)
        public
    {
        _checkOffers(buyOffer, buySig, sellOffer, sellSig);

        uint256 amount = UtilsLib.min(
            buyOffer.assets - consumed[abi.encode(buyOffer)], sellOffer.assets - consumed[abi.encode(sellOffer)]
        );
        require(amount > 0, "No assets to match");
        address buyer = buyOffer.offering;
        address seller = sellOffer.offering;

        consumed[abi.encode(buyOffer)] += amount;
        consumed[abi.encode(sellOffer)] += amount;

        Term memory term = Term(sellOffer.loanToken, sellOffer.collaterals, sellOffer.maturity);
        bytes32 id = _id(term);

        uint256 repaid = UtilsLib.min(debtOf[buyer][id], amount);
        uint256 bought = amount - repaid;
        uint256 boughtShares = bought.toSharesDown(totalAssets[id], totalShares[id]);
        debtOf[buyer][id] -= repaid;
        bondSharesOf[buyer][id] += boughtShares;

        uint256 withdrawn;
        uint256 withdrawnShares;

        if (bondSharesOf[seller][id].toAssetsDown(totalAssets[id], totalShares[id]) < amount) {
            withdrawn = bondSharesOf[seller][id].toAssetsDown(totalAssets[id], totalShares[id]);
            withdrawnShares = bondSharesOf[seller][id];
        } else {
            withdrawn = amount;
            withdrawnShares = amount.toSharesUp(totalAssets[id], totalShares[id]);
        }

        bondSharesOf[seller][id] -= withdrawnShares;
        debtOf[seller][id] += amount - withdrawn;

        totalShares[id] += boughtShares;
        totalShares[id] -= withdrawnShares;
        totalAssets[id] += bought;
        totalAssets[id] -= withdrawn;

        require(debtOf[buyer][id] == 0 || _isHealthy(term, buyer), "Buyer is unhealthy");
        require(debtOf[seller][id] == 0 || _isHealthy(term, seller), "Seller is unhealthy");

        uint256 sellerScaledPrice = sellOffer.price * amount / sellOffer.assets;
        uint256 buyerScaledPrice = buyOffer.price * amount / buyOffer.assets;

        IERC20(buyOffer.loanToken).transferFrom(buyer, seller, sellerScaledPrice);
        IERC20(buyOffer.loanToken).transferFrom(buyer, msg.sender, buyerScaledPrice - sellerScaledPrice);
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 amount, uint256 shares, address onBehalf) external {
        require(UtilsLib.exactlyOneZero(amount, shares), "INCONSISTENT_INPUT");
        bytes32 id = _id(term);

        if (amount > 0) shares = amount.toSharesUp(totalAssets[id], totalShares[id]);
        else amount = shares.toAssetsDown(totalAssets[id], totalShares[id]);

        bondSharesOf[onBehalf][id] -= shares;
        withdrawable[id] -= amount;

        totalShares[id] -= shares;
        totalAssets[id] -= amount;

        IERC20(term.loanToken).transfer(msg.sender, amount);
    }

    function repayDebt(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = _id(term);

        debtOf[onBehalf][id] -= amount;
        withdrawable[id] += amount;

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), amount);
    }

    function supplyCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] += amount;
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] -= amount;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        IERC20(collateral).transfer(msg.sender, amount);
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrower`.
    /// @dev On each seizure either `repaidAmounts` or `seizedAssets` should be equal to zero.
    /// @param term The term of the bond.
    /// @param seizures An array of amounts of debt to repay or assets to seize with the index of the collateral in the term's collateral assets.
    /// @param borrower The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return A collection of the actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(Term memory term, Seizure[] memory seizures, address borrower, bytes calldata data)
        external
        returns (Seizure[] memory)
    {
        require(seizures.length == term.collaterals.length, "should have all collats");

        bytes32 id = _id(term);
        uint256 liquidationIncentiveFactor = 1.15e18;

        uint256 maxDebt;
        uint256 repayableDebt;

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            uint256 price = IOracle(term.collaterals[i].oracle).price();
            uint256 collateralQuoted =
                collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
            maxDebt += collateralQuoted.wMulDown(term.collaterals[i].lltv);
            repayableDebt += collateralQuoted.wDivUp(liquidationIncentiveFactor);
        }
        require(debtOf[borrower][id] >= maxDebt, "position is healthy");

        uint256 totalRepaid;

        for (uint256 i = 0; i < term.collaterals.length; i++) {
            if (seizures[i].repaidAmount + seizures[i].seizedAssets > 0) {
                require(
                    UtilsLib.exactlyOneZero(seizures[i].repaidAmount, seizures[i].seizedAssets), "INCONSISTENT_INPUT"
                );

                uint256 collateralPrice = IOracle(term.collaterals[i].oracle).price();

                if (seizures[i].seizedAssets > 0) {
                    seizures[i].repaidAmount = seizures[i].seizedAssets.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
                        .wDivUp(liquidationIncentiveFactor);
                } else {
                    seizures[i].seizedAssets = seizures[i].repaidAmount.wMulDown(liquidationIncentiveFactor).mulDivDown(
                        ORACLE_PRICE_SCALE, collateralPrice
                    );
                }

                totalRepaid += seizures[i].repaidAmount;
                collateralOf[borrower][id][term.collaterals[i].token] -= seizures[i].seizedAssets;

                IERC20(term.collaterals[i].token).transfer(msg.sender, seizures[i].seizedAssets);
            }
        }

        uint256 originalDebt = debtOf[borrower][id];
        debtOf[borrower][id] -= totalRepaid;

        // Realize bad debt
        if (repayableDebt < originalDebt) {
            // Because roundings are not aligned the effective bad debt is either the remaining debt or the original debt minus the theoretical repayable debt.
            uint256 badDebt = UtilsLib.min(debtOf[borrower][id], originalDebt - repayableDebt);
            debtOf[borrower][id] -= badDebt;
            totalAssets[id] -= badDebt;
        }

        withdrawable[id] += totalRepaid;

        if (data.length > 0) IMorphoLiquidationCallback(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), totalRepaid);

        return seizures;
    }

    //@dev It is always possible to mint at par because a user can
    //match with himself - using two different addresses - and
    //flash-loan collateral by following these steps: flashloan;
    //borrow/lend at par to mint X bonds; repay as borrower; withdraw
    //collateral to repay flashloan; lender address has now X bonds
    //and there's X withdrawable lent assets; note however that the
    //value (not the amount) of bond could be lesser than of the loan
    //asset, in case of accounted bad debt.
    function mintAtPar(Term memory term, uint256 debt, address onBehalf) public {
        bytes32 id = _id(term);

        // Maybe we could relax this restriction and just offset the
        // current debt and merge the function with repay.
        require(debtOf[onBehalf][id] == 0 || _isHealthy(term, onBehalf), "Buyer is unhealthy");

        bondSharesOf[onBehalf][id] += debt.toSharesDown(totalAssets[id], totalShares[id]);
        withdrawable[id] += debt;

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), debt);
    }

    function bondOf(address owner, bytes32 id) public view returns (uint256) {
        return bondSharesOf[owner][id].toAssetsDown(totalAssets[id], totalShares[id]);
    }

    /// INTERNAL ///

    function _id(Term memory term) public pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function _checkOffers(
        Offer memory buyOffer,
        Signature memory buySig,
        Offer memory sellOffer,
        Signature memory sellSig
    ) internal view {
        // Check consistency.

        require(buyOffer.buy && !sellOffer.buy, "Inconsistent lend flags");
        require(buyOffer.maturity > block.timestamp, "Buy offer has expired");
        _checkSignature(buyOffer, buySig);
        _checkSignature(sellOffer, sellSig);

        // Check compatibility.

        require(buyOffer.offering != sellOffer.offering, "Same offering");
        require(buyOffer.loanToken == sellOffer.loanToken, "Loan tokens do not match");
        uint256 j = 0;
        for (uint256 i = 0; i < sellOffer.collaterals.length; i++) {
            // Relies on the fact that the collaterals are sorted.
            // Note that we actually never check that.
            // If they are not, the match could fail.
            while (
                bytes20(sellOffer.collaterals[i].token) < bytes20(buyOffer.collaterals[j].token)
                    && j++ < buyOffer.collaterals.length
            ) {}
            require(sellOffer.collaterals[i].token == buyOffer.collaterals[j].token, "Collaterals tokens do not match");
            require(sellOffer.collaterals[i].lltv <= buyOffer.collaterals[j].lltv, "LLTVs do not match");
            require(sellOffer.collaterals[i].oracle == buyOffer.collaterals[j].oracle, "Oracles do not match");
            j++;
        }
        require(buyOffer.maturity == sellOffer.maturity, "Maturities do not match");
        require(buyOffer.price >= sellOffer.price, "Buy offer price is less than sell offer price");
    }

    function _checkSignature(Offer memory offer, Signature memory signature) internal view {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && offer.offering == signatory, "Invalid signature");
    }

    function _isHealthy(Term memory term, address borrower) internal view returns (bool) {
        if (term.maturity < block.timestamp) {
            return false;
        } else {
            bytes32 id = _id(term);

            uint256 maxDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.wMulDown(term.collaterals[i].lltv);
            }

            return debtOf[borrower][id] <= maxDebt;
        }
    }
}
