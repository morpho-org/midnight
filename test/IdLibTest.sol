// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";

// toMarket is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is Test {
    function baseMarket() internal pure returns (Market memory market) {
        market.chainId = 1;
        market.midnight = address(1);
        market.loanToken = address(2);
        market.collateralParams = new CollateralParams[](1);
        market.collateralParams[0] =
            CollateralParams({token: address(3), lltv: 0.77e18, liquidationCursor: 1.1e18, oracle: address(4)});
        market.maturity = 123;
        market.rcfThreshold = 456;
        market.enterGate = address(5);
        market.liquidatorGate = address(6);
    }

    function testToIdIsSensitiveToMarketParams() public pure {
        Market memory market1 = baseMarket();
        Market memory market2 = baseMarket();
        market2.chainId = 2;
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.midnight = address(7);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.loanToken = address(8);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.collateralParams[0].token = address(9);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.collateralParams[0].lltv = 0.5e18;
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.collateralParams[0].liquidationCursor = 1.2e18;
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.collateralParams[0].oracle = address(12);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.maturity = 789;
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.rcfThreshold = 789;
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.enterGate = address(10);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));

        market2 = baseMarket();
        market2.liquidatorGate = address(11);
        assertNotEq(IdLib.toId(market1), IdLib.toId(market2));
    }
}
