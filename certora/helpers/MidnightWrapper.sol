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

    // Explicit-price variant of realizableBadDebt: identical loop, but each collateral term is valued at
    // the EXPLICITLY PASSED `price` instead of the oracle's IOracle(...).price(). This decouples the
    // measurement price from the price liquidate reads at call time, letting a spec measure the realizable
    // bad debt at a DROPPED price p' <= p while liquidate still runs at p. Structurally a verbatim copy of
    // realizableBadDebt above (same zeroFloorSub, same mulDivUp(mulDivUp(collateral_i, price,
    // ORACLE_PRICE_SCALE), WAD, maxLif_i)), so the prover equates it with the production bad-debt math.
    function realizableBadDebtAtPrice(Market memory market, bytes32 id, address borrower, uint256 price)
        public
        view
        returns (uint256)
    {
        Position storage _position = position[id][borrower];
        uint256 badDebt = _position.debt;
        uint128 _collateralBitmap = _position.collateralBitmap;
        while (_collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(_collateralBitmap);
            CollateralParams memory _collateralParam = market.collateralParams[i];
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
