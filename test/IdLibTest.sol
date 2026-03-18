// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Lif, Obligation, Collateral} from "../src/interfaces/IMidnight.sol";
import {FuzzCollateral, FuzzObligation} from "./BaseTest.sol";

// toObligation is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is Test {
    function _toObligation(FuzzObligation memory fuzz) internal pure returns (Obligation memory o) {
        o.loanToken = fuzz.loanToken;
        o.maturity = fuzz.maturity;
        o.rcfThreshold = fuzz.rcfThreshold;
        o.collaterals = new Collateral[](fuzz.collaterals.length);
        for (uint256 i = 0; i < fuzz.collaterals.length; i++) {
            o.collaterals[i].token = fuzz.collaterals[i].token;
            o.collaterals[i].lltv = fuzz.collaterals[i].lltv;
            o.collaterals[i].maxLif = fuzz.collaterals[i].maxLif % 2 == 0 ? Lif.Low : Lif.High;
            o.collaterals[i].oracle = fuzz.collaterals[i].oracle;
        }
    }

    function testToIdIsInjectiveInObligation(
        FuzzObligation memory fuzzObligation1,
        FuzzObligation memory fuzzObligation2,
        uint256 chainid,
        address midnight
    ) public pure {
        Obligation memory obligation1 = _toObligation(fuzzObligation1);
        Obligation memory obligation2 = _toObligation(fuzzObligation2);
        bool sameLoanToken = obligation1.loanToken == obligation2.loanToken;
        bool sameMaturity = obligation1.maturity == obligation2.maturity;
        bool sameCollaterals = obligation1.collaterals.length == obligation2.collaterals.length;
        bool sameRcfThreshold = obligation1.rcfThreshold == obligation2.rcfThreshold;
        if (sameCollaterals) {
            for (uint256 i = 0; i < obligation1.collaterals.length; i++) {
                if (obligation1.collaterals[i].token != obligation2.collaterals[i].token) sameCollaterals = false;
                if (obligation1.collaterals[i].lltv != obligation2.collaterals[i].lltv) sameCollaterals = false;
                if (obligation1.collaterals[i].maxLif != obligation2.collaterals[i].maxLif) sameCollaterals = false;
                if (obligation1.collaterals[i].oracle != obligation2.collaterals[i].oracle) sameCollaterals = false;
            }
        }

        vm.assume(!(sameLoanToken && sameMaturity && sameCollaterals && sameRcfThreshold));

        bytes32 id1 = IdLib.toId(obligation1, chainid, midnight);
        bytes32 id2 = IdLib.toId(obligation2, chainid, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInChainId(
        FuzzObligation memory fuzzObligation,
        uint256 chainid1,
        uint256 chainid2,
        address midnight
    ) public pure {
        Obligation memory obligation = _toObligation(fuzzObligation);
        vm.assume(chainid1 != chainid2);
        bytes32 id1 = IdLib.toId(obligation, chainid1, midnight);
        bytes32 id2 = IdLib.toId(obligation, chainid2, midnight);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInMidnight(
        FuzzObligation memory fuzzObligation,
        uint256 chainid,
        address midnightOne,
        address midnightTwo
    ) public pure {
        Obligation memory obligation = _toObligation(fuzzObligation);
        vm.assume(midnightOne != midnightTwo);
        bytes32 id1 = IdLib.toId(obligation, chainid, midnightOne);
        bytes32 id2 = IdLib.toId(obligation, chainid, midnightTwo);
        assertNotEq(id1, id2);
    }
}
