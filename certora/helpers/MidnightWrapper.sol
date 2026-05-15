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
}
