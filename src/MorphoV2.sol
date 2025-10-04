// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMorphoV2.sol";
import "./interfaces/ICallbacks.sol";

contract MorphoV2 is IMorphoV2 {
    using MathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address maker,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 start,uint256 expiry,uint256 startPrice,uint256 expiryPrice,uint256 nonce)"
    );
    bytes32 public constant AUTHORIZATION_TYPEHASH =
        keccak256("Authorization(address authorizer,address authorizee,bool authorized,uint256 nonce,uint256 deadline)");

    uint256 public constant ORACLE_PRICE_SCALE = 1e36;
    uint256 public constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// STORAGE ///

    mapping(address => mapping(bytes32 => uint256)) public sharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalUnits;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    mapping(address => mapping(address => bool)) public authorized;
    mapping(address => uint256) public authorizationNonce;
    mapping(bytes => bool) public _ratified;

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    /// ENTRY-POINTS ///

    /// @dev Same function used to buy and sell.
    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    function take(
        Obligation memory obligation,
        uint256 assets,
        uint256 obligationUnits,
        address taker,
        Offer memory offer,
        Signature memory sig,
        address takerCallbackAddress,
        bytes memory takerCallbackData
    ) public {
        require(assets == 0 || obligationUnits == 0, "inconsistent input");
        require(block.timestamp >= offer.start, "offer not started");
        require(block.timestamp <= offer.expiry, "offer expired");
        require(obligation.maturity >= block.timestamp, "maturity");
        require(offer.loanToken == obligation.loanToken, "Loan tokens do not match");
        require(offer.maturity == obligation.maturity, "Maturities do not match");
        require(offer.start < offer.expiry || offer.expiryPrice == offer.startPrice, "inconsistent prices");
        require(msg.sender == taker || authorized[taker][msg.sender], "order not authorized");
        require(
            msg.sender == offer.maker
                || (
                    offer.ratifier != address(0) && authorized[offer.maker][offer.ratifier]
                        && ICallbacks(offer.ratifier).onRatify(obligation, offer, sig)
                ) || (sig.v != 0 && _signatureIsValid(abi.encode(OFFER_TYPEHASH, offer), sig, offer.maker))
                || authorized[offer.maker][msg.sender] || _ratified[abi.encode(offer)],
            "offer not ratified"
        );
        _checkCollateralInclusion(obligation, offer);

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

        uint256 price = offer.expiry != offer.start
            ? offer.startPrice
                + (offer.expiryPrice - offer.startPrice) * (block.timestamp - offer.start) / (offer.expiry - offer.start)
            : offer.startPrice;

        if (assets > 0) obligationUnits = assets.mulDivDown(1e18, price);
        else assets = obligationUnits.mulDivDown(price, 1e18);

        require((consumed[offer.maker][offer.nonce] += assets) <= offer.assets, "consumed");

        bytes32 id = _id(obligation);

        uint256 repaid = UtilsLib.min(debtOf[buyer][id], obligationUnits);
        uint256 bought = obligationUnits - repaid;
        uint256 boughtShares = bought.mulDivDown(totalShares[id] + 1, totalUnits[id] + 1);
        uint256 withdrawn =
            UtilsLib.min(sharesOf[seller][id].mulDivDown(totalUnits[id] + 1, totalShares[id] + 1), obligationUnits);
        uint256 withdrawnShares = withdrawn.mulDivUp(totalShares[id] + 1, totalUnits[id] + 1);

        debtOf[buyer][id] -= repaid;
        sharesOf[buyer][id] += boughtShares;
        sharesOf[seller][id] -= withdrawnShares;
        debtOf[seller][id] += obligationUnits - withdrawn;

        totalShares[id] += boughtShares;
        totalShares[id] -= withdrawnShares;
        totalUnits[id] += bought;
        totalUnits[id] -= withdrawn;

        if (buyerCallbackAddress != address(0)) {
            ICallbacks(buyerCallbackAddress).onTake(obligation, buyer, assets, buyerCallbackData);
        }

        SafeTransferLib.safeTransferFrom(offer.loanToken, buyer, seller, assets);

        if (sellerCallbackAddress != address(0)) {
            ICallbacks(sellerCallbackAddress).onTake(obligation, seller, assets, sellerCallbackData);
        }

        require(_isHealthy(obligation, seller), "Seller is unhealthy");
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares, address onBehalf)
        external
    {
        require(UtilsLib.exactlyOneZero(obligationUnits, shares), "INCONSISTENT_INPUT");
        bytes32 id = _id(obligation);

        if (obligationUnits > 0) shares = obligationUnits.mulDivUp(totalShares[id] + 1, totalUnits[id] + 1);
        else obligationUnits = shares.mulDivDown(totalUnits[id] + 1, totalShares[id] + 1);

        sharesOf[onBehalf][id] -= shares;
        withdrawable[id] -= obligationUnits;

        totalShares[id] -= shares;
        totalUnits[id] -= obligationUnits;

        SafeTransferLib.safeTransfer(obligation.loanToken, msg.sender, obligationUnits);
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
        collateralOf[onBehalf][_id(obligation)][collateral] -= assets;

        require(_isHealthy(obligation, onBehalf), "Unhealthy borrower");

        SafeTransferLib.safeTransfer(collateral, msg.sender, assets);
    }

    /// @notice Execute the given collection of `seizures` on the given `obligation` of the given `borrower`.
    /// @dev On each seizure either `repaid` or `seized` should be equal to zero.
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
            maxDebt += collateralAmount.mulDivDown(prices[i], ORACLE_PRICE_SCALE).mulDivDown(
                obligation.collaterals[i].lltv, 1e18
            );
            repayableDebt +=
                collateralAmount.mulDivUp(prices[i], ORACLE_PRICE_SCALE).mulDivUp(1e18, LIQUIDATION_INCENTIVE_FACTOR);
        }

        uint256 originalDebt = debtOf[borrower][id];
        require(originalDebt > maxDebt, "position is healthy");

        uint256 badDebt = originalDebt.zeroFloorSub(repayableDebt);
        if (badDebt > 0) {
            debtOf[borrower][id] -= badDebt;
            totalUnits[id] -= badDebt;
        }

        uint256 totalRepaid;

        for (uint256 i = 0; i < seizures.length; i++) {
            Seizure memory seizure = seizures[i];
            require(UtilsLib.exactlyOneZero(seizure.repaid, seizure.seized), "INCONSISTENT_INPUT");

            if (seizure.seized > 0) {
                seizure.repaid = seizure.seized.mulDivUp(prices[seizure.collateralIndex], ORACLE_PRICE_SCALE).mulDivUp(
                    1e18, LIQUIDATION_INCENTIVE_FACTOR
                );
            } else {
                seizure.seized = seizure.repaid.mulDivDown(LIQUIDATION_INCENTIVE_FACTOR, 1e18).mulDivDown(
                    ORACLE_PRICE_SCALE, prices[seizure.collateralIndex]
                );
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

    function ratified(Offer memory offer) external view returns (bool) {
        return _ratified[abi.encode(offer)];
    }

    /// @dev No ratification by signature, check the signature in the caller.
    function setRatified(Offer memory offer, bool newRatified) external {
        require(msg.sender == offer.maker || authorized[offer.maker][msg.sender], "ratification not authorized");
        _ratified[abi.encode(offer)] = newRatified;
    }

    function setAuthorized(address authorizee, bool newAuthorized) external {
        authorized[msg.sender][authorizee] = newAuthorized;
    }

    function setAuthorizedWithSig(Authorization memory authorization, Signature calldata signature) external {
        /// Do not check whether authorization is already set because the nonce increment is a desired side effect.
        require(block.timestamp <= authorization.deadline, "expired");
        require(authorization.nonce == authorizationNonce[authorization.authorizer]++, "invalid nonce");
        require(
            _signatureIsValid(abi.encode(AUTHORIZATION_TYPEHASH, authorization), signature, authorization.authorizer),
            "invalid signature"
        );

        authorized[authorization.authorizer][authorization.authorizee] = authorization.authorized;
    }

    /// INTERNAL ///

    function _id(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function _checkCollateralInclusion(Obligation memory obligation, Offer memory offer) internal pure {
        Collateral[] memory subset = offer.buy ? obligation.collaterals : offer.collaterals;
        Collateral[] memory superset = offer.buy ? offer.collaterals : obligation.collaterals;

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
        return signatory != address(0) && offer.maker == signatory;
    }

    function _isHealthy(Obligation memory obligation, address borrower) internal view returns (bool) {
        bytes32 id = _id(obligation);
        uint256 debt = debtOf[borrower][id];
        if (debt == 0) {
            return true;
        } else {
            uint256 maxDebt;
            for (uint256 i = 0; i < obligation.collaterals.length; i++) {
                uint256 price = IOracle(obligation.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    collateralOf[borrower][id][obligation.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.mulDivDown(obligation.collaterals[i].lltv, 1e18);
            }

            return debt <= maxDebt;
        }
    }

    function _signatureIsValid(bytes memory typedStruct, Signature memory signature, address expectedSignatory)
        internal
        view
        returns (bool)
    {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, keccak256(typedStruct)));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        return signatory != address(0) && signatory == expectedSignatory;
    }
}
