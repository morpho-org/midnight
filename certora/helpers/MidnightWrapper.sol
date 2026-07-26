// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Position, CollateralParams, Market} from "../../src/interfaces/IMidnight.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {ORACLE_PRICE_SCALE, WAD, maxLif} from "../../src/libraries/ConstantsLib.sol";

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

    /* maxRepaidFor recomputes the RCF cap of Midnight.liquidate (see src/Midnight.sol:699) through a
     * bitmap-free, array-based code path. maxDebt is summed exactly as in isHealthyNoBitmap and the
     * liquidate bad-debt loop, then the L699 mulDivUp is applied with lif = maxLif (normal mode).
     * Expects the position to be unhealthy (debt > maxDebt) so that debt - maxDebt does not underflow. */
    function maxRepaidFor(Market memory market, bytes32 id, uint256 collateralIndex, address borrower)
        public
        view
        returns (uint256)
    {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        uint256 len = market.collateralParams.length;
        for (uint256 i = len; i > 0;) {
            i--;
            CollateralParams memory collateralParam = market.collateralParams[i];
            uint256 price = IOracle(collateralParam.oracle).price();
            maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE)
                .mulDivDown(collateralParam.lltv, WAD);
        }
        CollateralParams memory liquidatedParam = market.collateralParams[collateralIndex];
        uint256 lltv = liquidatedParam.lltv;
        uint256 lif = maxLif(lltv, liquidatedParam.liquidationCursor);
        return (debt - maxDebt).mulDivUp(WAD * WAD, WAD * WAD - lif * lltv);
    }

    /* badDebtFor recomputes the badDebt of Midnight.liquidate (see src/Midnight.sol:643-655) through a
     * bitmap-free, array-based code path. Used to pin the no-bad-debt case (badDebtFor == 0), under which
     * liquidate does not reduce _position.debt before the L699 cap computation. */
    function badDebtFor(Market memory market, bytes32 id, address borrower) public view returns (uint256) {
        Position storage _position = position[id][borrower];
        uint256 badDebt = _position.debt;
        uint256 len = market.collateralParams.length;
        for (uint256 i = len; i > 0;) {
            i--;
            CollateralParams memory collateralParam = market.collateralParams[i];
            uint256 price = IOracle(collateralParam.oracle).price();
            badDebt = badDebt.zeroFloorSub(
                _position.collateral[i].mulDivUp(price, ORACLE_PRICE_SCALE)
                    .mulDivUp(WAD, maxLif(collateralParam.lltv, collateralParam.liquidationCursor))
            );
        }
        return badDebt;
    }
}
