// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./libraries/Math.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";

contract Terms is ITerms {
    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 price)"
    );
    uint256 public constant WAD = 1 ether;

    /// STORAGE ///

    // Terms.
    mapping(address => mapping(bytes32 => uint256)) public bondOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    // Offers.
    mapping(bytes => uint256) public consumed;

    /// ENTRY-POINTS ///

    /// @dev This function is used for both primary and secondary markets.
    function MATCH(Offer memory buyOffer, Signature memory buySig, Offer memory sellOffer, Signature memory sellSig)
        public
    {
        _checkOffers(buyOffer, buySig, sellOffer, sellSig);

        uint256 amount = Math.min(
            buyOffer.assets - consumed[abi.encode(buyOffer)], sellOffer.assets - consumed[abi.encode(sellOffer)]
        );
        require(amount > 0, "No assets to match");
        address buyer = buyOffer.offering;
        address seller = sellOffer.offering;

        consumed[abi.encode(buyOffer)] += amount;
        consumed[abi.encode(sellOffer)] += amount;

        Term memory term = Term(sellOffer.loanToken, sellOffer.collaterals, sellOffer.maturity);
        bytes32 id = _id(term);

        uint256 repaid = Math.min(debtOf[buyer][id], amount);
        debtOf[buyer][id] -= repaid;
        bondOf[buyer][id] += amount - repaid;

        uint256 withdrawn = Math.min(bondOf[seller][id], amount);
        bondOf[seller][id] -= withdrawn;
        debtOf[seller][id] += amount - withdrawn;

        // Callback execution
        if (buyOffer.callback.callbackAddress != address(0)) {
            (bool buyCallbackSuccess,) = buyOffer.callback.callbackAddress.call{gas: buyOffer.callback.callbackGasLimit}(
                buyOffer.callback.callbackData
            );
            require(buyCallbackSuccess, "Buyer callback revert");
        }

        uint256 sellerScaledPrice = sellOffer.price * amount / sellOffer.assets;
        uint256 buyerScaledPrice = buyOffer.price * amount / buyOffer.assets;

        IERC20(buyOffer.loanToken).transferFrom(buyer, seller, sellerScaledPrice);
        IERC20(buyOffer.loanToken).transferFrom(buyer, msg.sender, buyerScaledPrice - sellerScaledPrice);

        if (sellOffer.callback.callbackAddress != address(0)) {
            (bool sellCallbackSuccess,) = sellOffer.callback.callbackAddress.call{
                gas: sellOffer.callback.callbackGasLimit
            }(sellOffer.callback.callbackData);
            require(sellCallbackSuccess, "Seller callback revert");
        }

        require(debtOf[buyer][id] == 0 || _isHealthy(term, buyer), "Buyer is unhealthy");
        require(debtOf[seller][id] == 0 || _isHealthy(term, seller), "Seller is unhealthy");
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = _id(term);

        bondOf[onBehalf][id] -= amount;
        withdrawable[id] -= amount;

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
        for (uint256 i = 0; i < sellOffer.collaterals.length; i++) {
            uint256 j;
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
            bytes32 id = _id(Term(term.loanToken, term.collaterals, term.maturity));

            uint256 maxDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted = collateralOf[borrower][id][term.collaterals[i].token] * price / WAD;
                maxDebt += collateralQuoted * term.collaterals[i].lltv / WAD;
            }

            return debtOf[borrower][id] <= maxDebt;
        }
    }
}
