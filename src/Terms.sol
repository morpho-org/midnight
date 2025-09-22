// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/SafeTransferLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/IHooks.sol";
import "./interfaces/IMatching.sol";
import "./libraries/ConstantsLib.sol";

contract Terms is ITerms {
    using MathLib for uint256;

    /// EVENTS ///

    event SetRatified(address indexed sender, Offer offer, bool isRatified);
    event SetAuthorized(address indexed sender, address indexed spender, bool authorized);

    /// CONSTANTS ///

    uint256 public constant ORACLE_PRICE_SCALE = 1e36;
    uint256 public constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// STORAGE ///

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address => mapping(uint256 => uint256)) public consumed;
    mapping(address => mapping(bytes32 => uint256)) public bondSharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtOf;
    mapping(bytes32 => uint256) public withdrawable;
    mapping(bytes32 => uint256) public totalBonds;
    mapping(bytes32 => uint256) public totalShares;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    mapping(address => mapping(address => bool)) public authorized;
    mapping(bytes => bool) public ratified;

    /// ENTRY-POINTS ///

    function take(Term memory term, Order memory order, Offer memory offer) external {
        require(block.timestamp >= offer.start, "offer offer not started");
        require(block.timestamp <= offer.expiry, "offer offer expired");
        require(term.maturity >= block.timestamp, "bond maturity");
        require(msg.sender == order.owner || authorized[order.owner][msg.sender], "order not authorized");
        require(
            msg.sender == offer.owner || authorized[offer.owner][msg.sender] || ratified[abi.encode(offer)],
            "offer not authorized"
        );
        require((consumed[offer.owner][offer.nonce] += order.assets) <= offer.assets, "consumed");
        IMatching(offer.matching).check(term, order.assets, order.bonds, offer);

        bytes32 id = _id(term);
        (address buyer, address seller) = offer.buying ? (offer.owner, order.owner) : (order.owner, offer.owner);

        uint256 repaid = UtilsLib.min(debtOf[buyer][id], order.bonds);
        uint256 bought = order.bonds - repaid;
        uint256 boughtShares = bought.mulDivDown(totalShares[id] + 1, totalBonds[id] + 1);
        uint256 withdrawn =
            UtilsLib.min(bondSharesOf[seller][id].mulDivDown(totalBonds[id] + 1, totalShares[id] + 1), order.bonds);
        uint256 withdrawnShares = withdrawn.mulDivUp(totalShares[id] + 1, totalBonds[id] + 1);
        uint256 borrowed = order.bonds - withdrawn;

        if (offer.owner == buyer) require((offer.asBorrower ? bought : repaid) == 0, "buyer role");
        else require((offer.asBorrower ? withdrawn : borrowed) == 0, "seller role");

        debtOf[buyer][id] -= repaid;
        bondSharesOf[buyer][id] += boughtShares;
        bondSharesOf[seller][id] -= withdrawnShares;
        debtOf[seller][id] += borrowed;

        totalShares[id] += boughtShares;
        totalShares[id] -= withdrawnShares;
        totalBonds[id] += bought;
        totalBonds[id] -= withdrawn;

        (address buyHook, bytes memory buyHookData, address sellHook, bytes memory sellHookData) = offer.buying
            ? (offer.hook, offer.hookData, order.hook, order.hookData)
            : (order.hook, order.hookData, offer.hook, offer.hookData);

        if (buyHook != address(0)) {
            IBuyer(buyHook).onBuy(term, order.assets, order.bonds, buyer, buyHookData);
        }

        SafeTransferLib.safeTransferFrom(term.loanToken, buyer, seller, order.assets);

        if (sellHook != address(0)) ISeller(sellHook).onSell(term, order.assets, order.bonds, seller, sellHookData);

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

        if (data.length > 0) ILiquidator(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        SafeTransferLib.safeTransferFrom(term.loanToken, msg.sender, address(this), totalRepaid);

        return seizures;
    }

    function setAuthorized(address spender, bool isAuthorized) external {
        authorized[msg.sender][spender] = isAuthorized;
        emit SetAuthorized(msg.sender, spender, isAuthorized);
    }

    /// @dev If the caller is the owner or is authorized by the owner, the last 2 arguments are ignored.
    function setRatified(Offer memory offer, bool isRatified) external {
        require(msg.sender == offer.owner || authorized[offer.owner][msg.sender], "ratification not authorized");
        ratified[abi.encode(offer)] = isRatified;
        emit SetRatified(msg.sender, offer, isRatified);
    }

    function setRatifiedByCallback(Offer memory offer, bool isRatified, bytes memory data) external {
        require(
            IRatifier(offer.owner).checkRatified(offer, isRatified, data) == RATIFICATION_RESPONSE,
            "Invalid ratification callback response"
        );
        ratified[abi.encode(offer)] = isRatified;
        emit SetRatified(msg.sender, offer, isRatified);
    }

    function setRatifiedBySignature(Offer memory offer, bool isRatified, Signature calldata signature) external {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        require(offer.owner != address(0) && offer.owner == signatory, "Invalid ratification signature");
        ratified[abi.encode(offer)] = isRatified;
        emit SetRatified(msg.sender, offer, isRatified);
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
}
