// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Position, CollateralParams, Market} from "../../src/interfaces/IMidnight.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {ORACLE_PRICE_SCALE, WAD} from "../../src/libraries/ConstantsLib.sol";

contract MidnightWrapper is Midnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /* This isHealthy function iterates over all collateralParams, it doesn't use the collateral bitmap. */

    function isHealthyNoBitmap(Market memory market, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        if (debt > 0) {
            uint256 len = market.collateralParams.length;
            for (uint256 i = len; i > 0;) {
                i--;
                CollateralParams memory collateralParam = market.collateralParams[i];
                uint256 price = IOracle(collateralParam.oracle).price();
                maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE)
                    .mulDivDown(collateralParam.lltv, WAD);
            }
        }
        return maxDebt >= debt;
    }

    /// @dev Mirrors the normal-mode liquidation pre-loop and the requested max-action selector for Certora specs.
    /// The returned input is the user's requested selector: full collateral seizure when the RCF residual is below
    /// `market.rcfThreshold`, otherwise repayment of `min(maxRepaid, debtAfterBadDebt)`.
    /// Extra returned values let the spec state the necessary fit assumptions explicitly: the requested selector is not
    /// always executable if full seizure would over-repay debt or if a repay input would over-seize collateral.
    function normalModeMaxLiquidationPreview(
        Market memory market,
        bytes32 id,
        uint256 collateralIndex,
        address borrower
    )
        public
        view
        returns (
            uint256 seizedAssets,
            uint256 repaidUnits,
            uint256 maxDebt,
            uint256 badDebt,
            uint256 debtAfterBadDebt,
            uint256 liquidatedCollatPrice,
            uint256 collateral,
            uint256 maxRepaid,
            bool rcfThresholdBypassed,
            uint256 fullSeizeRepaid,
            uint256 repayInputSeized
        )
    {
        Position storage _position = position[id][borrower];
        uint256 originalDebt = _position.debt;
        badDebt = originalDebt;

        uint128 _collateralBitmap = _position.collateralBitmap;
        while (_collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(_collateralBitmap);
            CollateralParams memory _collateralParam = market.collateralParams[i];
            uint256 price = IOracle(_collateralParam.oracle).price();
            if (i == collateralIndex) liquidatedCollatPrice = price;
            uint256 _collateral = _position.collateral[i];
            maxDebt += _collateral.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(_collateralParam.lltv, WAD);
            badDebt = badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
            );
            _collateralBitmap = _collateralBitmap.clearBit(i);
        }

        debtAfterBadDebt = originalDebt - badDebt;
        collateral = _position.collateral[collateralIndex];

        uint256 lif = market.collateralParams[collateralIndex].maxLif;
        uint256 lltv = market.collateralParams[collateralIndex].lltv;
        if (lltv < WAD) {
            uint256 lifTimesLltv = type(uint256).max;
            if (lltv == 0 || lif <= type(uint256).max / lltv) lifTimesLltv = lif * lltv;
            if (originalDebt > maxDebt && lifTimesLltv < WAD * WAD) {
                maxRepaid = (originalDebt - maxDebt).mulDivUp(WAD * WAD, WAD * WAD - lifTimesLltv);
            }
        } else {
            maxRepaid = type(uint256).max;
        }

        if (lif > 0 && liquidatedCollatPrice > 0) {
            uint256 collateralRepayableAfterMaxRepaid = collateral.mulDivDown(liquidatedCollatPrice, ORACLE_PRICE_SCALE)
                .mulDivDown(WAD, lif).zeroFloorSub(maxRepaid);
            rcfThresholdBypassed = collateralRepayableAfterMaxRepaid < market.rcfThreshold;
            fullSeizeRepaid = collateral.mulDivUp(liquidatedCollatPrice, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif);

            if (rcfThresholdBypassed) {
                seizedAssets = collateral;
            } else {
                repaidUnits = UtilsLib.min(maxRepaid, debtAfterBadDebt);
                repayInputSeized =
                    repaidUnits.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, liquidatedCollatPrice);
            }
        }
    }
}
