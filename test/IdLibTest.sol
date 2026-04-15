// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Obligation} from "../src/interfaces/IMidnight.sol";

// toObligation is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is Test {
    function testToIdIsInjectiveInObligation(
        Obligation memory obligation1,
        Obligation memory obligation2,
        uint256 chainid,
        address midnight
    ) public pure {
        bool sameLoanToken = obligation1.loanToken == obligation2.loanToken;
        bool sameMaturity = obligation1.maturity == obligation2.maturity;
        bool sameCollaterals = obligation1.collateralParams.length == obligation2.collateralParams.length;
        bool sameRcfThreshold = obligation1.rcfThreshold == obligation2.rcfThreshold;
        if (sameCollaterals) {
            for (uint256 i = 0; i < obligation1.collateralParams.length; i++) {
                if (obligation1.collateralParams[i].token != obligation2.collateralParams[i].token) {
                    sameCollaterals = false;
                }
                if (obligation1.collateralParams[i].lltv != obligation2.collateralParams[i].lltv) {
                    sameCollaterals = false;
                }
                if (obligation1.collateralParams[i].maxLif != obligation2.collateralParams[i].maxLif) {
                    sameCollaterals = false;
                }
                if (obligation1.collateralParams[i].oracle != obligation2.collateralParams[i].oracle) {
                    sameCollaterals = false;
                }
            }
        }

        vm.assume(!(sameLoanToken && sameMaturity && sameCollaterals && sameRcfThreshold));

        bytes32 id1 = IdLib.toId(obligation1, chainid, midnight);
        bytes32 id2 = IdLib.toId(obligation2, chainid, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInChainId(
        Obligation memory obligation,
        uint256 chainid1,
        uint256 chainid2,
        address midnight
    ) public pure {
        vm.assume(chainid1 != chainid2);
        bytes32 id1 = IdLib.toId(obligation, chainid1, midnight);
        bytes32 id2 = IdLib.toId(obligation, chainid2, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInMidnight(
        Obligation memory obligation,
        uint256 chainid,
        address midnightOne,
        address midnightTwo
    ) public pure {
        vm.assume(midnightOne != midnightTwo);
        bytes32 id1 = IdLib.toId(obligation, chainid, midnightOne);
        bytes32 id2 = IdLib.toId(obligation, chainid, midnightTwo);
        assertNotEq(id1, id2);
    }
}
