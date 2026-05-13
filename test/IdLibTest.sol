// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Market} from "../src/interfaces/IMidnight.sol";

// toMarket is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is Test {
    function testToIdIsInjectiveInMarket(
        Market memory market1,
        Market memory market2,
        uint256 chainid,
        address midnight
    ) public pure {
        bool sameLoanToken = market1.loanToken == market2.loanToken;
        bool sameMaturity = market1.maturity == market2.maturity;
        bool sameCollaterals = market1.collateralParams.length == market2.collateralParams.length;
        bool sameRcfThreshold = market1.rcfThreshold == market2.rcfThreshold;
        if (sameCollaterals) {
            for (uint256 i = 0; i < market1.collateralParams.length; i++) {
                if (market1.collateralParams[i].token != market2.collateralParams[i].token) {
                    sameCollaterals = false;
                }
                if (market1.collateralParams[i].lltv != market2.collateralParams[i].lltv) {
                    sameCollaterals = false;
                }
                if (market1.collateralParams[i].maxLif != market2.collateralParams[i].maxLif) {
                    sameCollaterals = false;
                }
                if (market1.collateralParams[i].oracle != market2.collateralParams[i].oracle) {
                    sameCollaterals = false;
                }
            }
        }

        vm.assume(!(sameLoanToken && sameMaturity && sameCollaterals && sameRcfThreshold));

        bytes32 id1 = IdLib.toId(market1, chainid, midnight);
        bytes32 id2 = IdLib.toId(market2, chainid, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInChainId(Market memory market, uint256 chainid1, uint256 chainid2, address midnight)
        public
        pure
    {
        vm.assume(chainid1 != chainid2);
        bytes32 id1 = IdLib.toId(market, chainid1, midnight);
        bytes32 id2 = IdLib.toId(market, chainid2, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInMidnight(
        Market memory market,
        uint256 chainid,
        address midnightOne,
        address midnightTwo
    ) public pure {
        vm.assume(midnightOne != midnightTwo);
        bytes32 id1 = IdLib.toId(market, chainid, midnightOne);
        bytes32 id2 = IdLib.toId(market, chainid, midnightTwo);
        assertNotEq(id1, id2);
    }
}
