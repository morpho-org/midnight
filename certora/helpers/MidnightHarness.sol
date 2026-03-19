// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Obligation, Position, Collateral} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../../src/libraries/ConstantsLib.sol";

contract MidnightHarness is Midnight {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    constructor() {}

    function isHealthyAfterContinuousFeeAccrual(Obligation memory obligation, bytes32 id, address borrower)
        external
        view
        returns (bool)
    {
        Position storage _position = position[id][borrower];
        uint256 debt = _position.debt + accrueContinuousFeeView(obligation, id, borrower);
        uint256 maxDebt;
        uint256 bitmap = _position.activatedCollaterals;
        while (maxDebt < debt && bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory collateral = obligation.collaterals[i];
            uint256 price = IOracle(collateral.oracle).price();
            maxDebt += _position.collateral[i].mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(collateral.lltv, WAD);
            bitmap ^= (1 << i);
        }
        return maxDebt >= debt;
    }
}
