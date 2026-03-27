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
    
    /* This isHealthy function iterates over all collaterals, it doesn't use the collateral bitmap. */

    function isHealthyNoBitmap(Obligation memory obligation, bytes32 id, address borrower) public view returns (bool) {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt;
        uint256 maxDebt;
        uint256 len = obligation.collaterals.length;
        for (uint256 i = len; i > 0 && maxDebt < debt; ) {
            i--;
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(collateral.lltv, WAD);
        }
        return maxDebt >= debt;
    }
}
