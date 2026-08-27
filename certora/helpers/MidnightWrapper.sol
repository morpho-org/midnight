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

    // This realizableBadDebt function recomputes, verbatim, the badDebt local that
    // liquidate() computes at src/Midnight.sol:643-657, so that the prover can equate this
    // getter's result with liquidate's inlined bad-debt computation.
    //
    // realizableBadDebt(id, borrower)
    //   = zeroFloorSub(debt, SUM over active-collateral i of
    //       ceil(ceil(collateral_i * price_i / ORACLE_PRICE_SCALE) * WAD / maxLif_i)).
    //
    // id is taken explicitly (mirroring isHealthyNoBitmap) and must be the id derived from
    // market; the caller passes the matching Market, exactly as liquidate does.
    function realizableBadDebt(Market memory market, bytes32 id, address borrower) public view returns (uint256) {
        Position storage _position = position[id][borrower];
        uint256 badDebt = _position.debt;
        uint128 _collateralBitmap = _position.collateralBitmap;
        while (_collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(_collateralBitmap);
            CollateralParams memory _collateralParam = market.collateralParams[i];
            uint256 price = IOracle(_collateralParam.oracle).price();
            uint256 _collateral = _position.collateral[i];
            badDebt = badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE)
                    .mulDivUp(WAD, maxLif(_collateralParam.lltv, _collateralParam.liquidationCursor))
            );
            _collateralBitmap = _collateralBitmap.clearBit(i);
        }
        return badDebt;
    }
}
