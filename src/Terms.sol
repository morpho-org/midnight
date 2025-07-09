// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./libraries/UtilsLib.sol";
import "./libraries/MathLib.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";
import "./interfaces/IMorphoLiquidationCallback.sol";
import "./interfaces/IHook.sol";

contract Terms is ITerms {
    using MathLib for uint256;

    /// CONSTANTS ///

    uint256 public constant ORACLE_PRICE_SCALE = 1e36;
    uint256 public constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    /// STORAGE ///

    mapping(address user => mapping(bytes32 termId => uint256)) public bondSharesOf;
    mapping(address user => mapping(bytes32 termId => uint256)) public debtOf;
    mapping(bytes32 termId => uint256) public withdrawable;
    mapping(bytes32 termId => uint256) public totalBonds;
    mapping(bytes32 termId => uint256) public totalShares;
    mapping(address user => mapping(bytes32 termId => mapping(address collateralToken => uint256))) public collateralOf;
    mapping(address user => mapping(address hook => bool)) public isHook;

    /// ENTRY-POINTS ///

    /// @dev If one wants to match two offers without taking a position, they can batch take them and not have a
    /// position at the end.
    /// @dev The hook of the maker is validated.
    function take(
        Term memory term,
        uint256 assets,
        uint256 bonds,
        address buyer,
        address buyerHook,
        bytes calldata buyerData,
        address seller,
        address sellerHook,
        bytes calldata sellerData
    ) external {
        require(term.maturity >= block.timestamp, "maturity");
        // TODO: implement isAuthorized
        // require(buyer == msg.sender || isAuthorized[buyer][msg.sender] || isHook[buyer][buyerHook], "not a hook");
        // require(seller == msg.sender || isAuthorized[seller][msg.sender] || isHook[buyer][buyerHook], "not a hook");

        bytes32 id = _id(term);

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

        if (buyerHook != address(0)) IHook(buyerHook).hook(term, assets, bonds, buyer, buyerData);
        IERC20(term.loanToken).transferFrom(buyer, seller, assets);
        if (sellerHook != address(0)) IHook(sellerHook).hook(term, assets, bonds, seller, sellerData);
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

        IERC20(term.loanToken).transfer(msg.sender, bonds);
    }

    function repayDebt(Term memory term, uint256 bonds, address onBehalf) external {
        bytes32 id = _id(term);

        debtOf[onBehalf][id] -= bonds;
        withdrawable[id] += bonds;

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), bonds);
    }

    function supplyCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] += assets;
        IERC20(collateral).transferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] -= assets;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        IERC20(collateral).transfer(msg.sender, assets);
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

                IERC20(term.collaterals[i].token).transfer(msg.sender, seizures[i].seizedAssets);
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

        if (data.length > 0) IMorphoLiquidationCallback(msg.sender).onLiquidate(seizures, borrower, msg.sender, data);

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), totalRepaid);

        return seizures;
    }

    function setHook(address hook, bool _isHook) external {
        isHook[msg.sender][hook] = _isHook;
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
