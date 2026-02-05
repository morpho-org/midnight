// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

// idToObligation is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is BaseTest {
    function testToIdIsInjectiveInObligation(
        Obligation memory obligation1,
        Obligation memory obligation2,
        uint256 chainid,
        address morphoV2
    ) public pure {
        boundObligation(obligation1);
        boundObligation(obligation2);
        bool sameLoanToken = obligation1.loanToken == obligation2.loanToken;
        bool sameMaturity = obligation1.maturity == obligation2.maturity;
        bool sameCollaterals = obligation1.collaterals.length == obligation2.collaterals.length;
        if (sameCollaterals) {
            for (uint256 i = 0; i < obligation1.collaterals.length; i++) {
                if (obligation1.collaterals[i].token != obligation2.collaterals[i].token) sameCollaterals = false;
                if (obligation1.collaterals[i].lltv != obligation2.collaterals[i].lltv) sameCollaterals = false;
                if (obligation1.collaterals[i].oracle != obligation2.collaterals[i].oracle) sameCollaterals = false;
            }
        }
        vm.assume(!(sameLoanToken && sameMaturity && sameCollaterals));

        bytes32 id1 = IdLib.toId(obligation1, chainid, morphoV2);
        bytes32 id2 = IdLib.toId(obligation2, chainid, morphoV2);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInChainId(
        Obligation memory obligation,
        uint256 chainid1,
        uint256 chainid2,
        address morphoV2
    ) public pure {
        boundObligation(obligation);
        vm.assume(chainid1 != chainid2);
        bytes32 id1 = IdLib.toId(obligation, chainid1, morphoV2);
        bytes32 id2 = IdLib.toId(obligation, chainid2, morphoV2);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInMorphoV2(
        Obligation memory obligation,
        uint256 chainid,
        address morphoV2One,
        address morphoV2Two
    ) public pure {
        boundObligation(obligation);
        vm.assume(morphoV2One != morphoV2Two);
        bytes32 id1 = IdLib.toId(obligation, chainid, morphoV2One);
        bytes32 id2 = IdLib.toId(obligation, chainid, morphoV2Two);
        assertNotEq(id1, id2);
    }

    function testRoundtrip(Obligation memory obligation) public {
        boundObligation(obligation);

        IdLib.storeInCode(obligation);

        bytes32 id = IdLib.toId(obligation, block.chainid, address(this));
        Obligation memory decoded = IdLib.idToObligation(id, address(this));

        assertEq(decoded.loanToken, obligation.loanToken);
        assertEq(decoded.maturity, obligation.maturity);
        assertEq(decoded.collaterals.length, obligation.collaterals.length);
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            assertEq(decoded.collaterals[i].token, obligation.collaterals[i].token);
            assertEq(decoded.collaterals[i].lltv, obligation.collaterals[i].lltv);
            assertEq(decoded.collaterals[i].oracle, obligation.collaterals[i].oracle);
        }
    }

    function testPackUnpackRoundtrip(Obligation memory obligation) public pure {
        boundObligation(obligation);

        bytes memory packed = IdLib.pack(obligation);
        Obligation memory decoded = IdLib.unpack(packed);

        assertEq(decoded.loanToken, obligation.loanToken);
        assertEq(decoded.maturity, obligation.maturity);
        assertEq(decoded.collaterals.length, obligation.collaterals.length);
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            assertEq(decoded.collaterals[i].token, obligation.collaterals[i].token);
            assertEq(decoded.collaterals[i].lltv, obligation.collaterals[i].lltv);
            assertEq(decoded.collaterals[i].oracle, obligation.collaterals[i].oracle);
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testUnpackEmptyReverts() public {
        vm.expectRevert();
        IdLib.unpack("");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackRejectsLargeLltv() public {
        Obligation memory obligation;
        obligation.collaterals = new Collateral[](1);
        obligation.collaterals[0].lltv = uint256(type(uint64).max) + 1;

        vm.expectRevert("lltv too large");
        IdLib.pack(obligation);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackRejectsLargeMaturity() public {
        Obligation memory obligation;
        obligation.maturity = uint256(type(uint64).max) + 1;

        vm.expectRevert("maturity too large");
        IdLib.pack(obligation);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPackRejectsTooManyCollaterals() public {
        Obligation memory obligation;
        obligation.collaterals = new Collateral[](uint256(type(uint8).max) + 1);

        vm.expectRevert("collateral count too large");
        IdLib.pack(obligation);
    }
}
