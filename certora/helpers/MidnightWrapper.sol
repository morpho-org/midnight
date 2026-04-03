// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Position, Collateral, Obligation} from "../../src/interfaces/IMidnight.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {ORACLE_PRICE_SCALE, WAD} from "../../src/libraries/ConstantsLib.sol";

contract MidnightWrapper is Midnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    /* This healthData function iterates over all collaterals, it doesn't use the collateral bitmap. */

    function healthDataNoBitmap(Obligation memory obligation, bytes32 id, address borrower, uint256 collateralIndex)
        public
        view
        returns (uint256 maxDebt, uint256 collatPrice, uint256 badDebt)
    {
        Position storage _position = position[id][borrower];
        badDebt = _position.debt;
        uint256 len = obligation.collaterals.length;
        for (uint256 i = len; i > 0;) {
            i--;
            uint256 _collateral = _position.collateral[i];
            if (_collateral == 0) continue;
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            if (i == collateralIndex) collatPrice = price;
            maxDebt += _collateral.mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(collateral.lltv, WAD);
            badDebt =
                badDebt.zeroFloorSub(_collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, collateral.maxLif));
        }
    }

    function isHealthyNoBitmap(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        if (UtilsLib.tGet(DEFERRED_CHECK_SLOT, id, borrower)) return true;
        if (position[id][borrower].debt == 0) {
            return true;
        } else {
            (uint256 maxDebt,,) = healthDataNoBitmap(obligation, id, borrower, 0);
            return maxDebt >= position[id][borrower].debt;
        }
    }
}
