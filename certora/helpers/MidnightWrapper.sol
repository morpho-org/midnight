// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Position, CollateralParams, Obligation} from "../../src/interfaces/IMidnight.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {ORACLE_PRICE_SCALE, WAD, DEFERRED_CHECK_SLOT} from "../../src/libraries/ConstantsLib.sol";

contract MidnightWrapper is Midnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /* This healthData function iterates over all collateralParams, it doesn't use the collateral bitmap. */
    function healthDataNoBitmap(Obligation memory obligation, bytes32 id, address borrower, uint256 collateralIndex)
        public
        view
        returns (uint256 maxDebt, uint256 collatPrice, uint256 badDebt)
    {
        if (UtilsLib.tGet(DEFERRED_CHECK_SLOT, id, borrower)) return (type(uint256).max, collatPrice, 0);
        Position storage _position = position[id][borrower];
        badDebt = _position.debt;
        uint256 len = obligation.collateralParams.length;
        for (uint256 i = len; i > 0;) {
            i--;
            uint256 _collateral = _position.collateral[i];
            if (_collateral == 0) continue;
            CollateralParams memory collateralParam = obligation.collateralParams[i];
            uint256 price = IOracle(collateralParam.oracle).price();
            if (i == collateralIndex) collatPrice = price;
            maxDebt += _collateral.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(collateralParam.lltv, WAD);
            badDebt =
                badDebt.zeroFloorSub(_collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, collateralParam.maxLif));
        }
    }

    function isHealthyNoBitmap(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        // collateralPrice is unused here, passing type(uint256).max as a dummy value.
        (uint256 maxDebt,,) = healthDataNoBitmap(obligation, id, borrower, type(uint256).max);
        return maxDebt >= position[id][borrower].debt;
    }
}
