// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IdLib} from "../src/libraries/IdLib.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract OtherFunctionsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testSupplyCollateral(address user, uint256 amount) public {
        vm.assume(user != address(morphoV2));
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), amount);
        ERC20(collateralToken).approve(address(morphoV2), amount);

        // Note: you can supply collaterals that are not in the obligation.
        morphoV2.supplyCollateral(obligation, collateralToken, amount, user);

        assertEq(morphoV2.collateralOf(id, user, collateralToken), amount, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), amount, "balance of morphoV2");
    }

    function testWithdrawCollateralNoBorrow(address user, uint256 supply, uint256 withdraw) public {
        vm.assume(user != address(morphoV2) && user != address(0));
        withdraw = bound(withdraw, 0, supply);
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), supply);
        ERC20(collateralToken).approve(address(morphoV2), supply);
        morphoV2.supplyCollateral(obligation, collateralToken, supply, user);

        vm.prank(user);
        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, user);

        assertEq(morphoV2.collateralOf(id, user, collateralToken), supply - withdraw, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), supply - withdraw, "balance of morphoV2");
        assertEq(ERC20(collateralToken).balanceOf(user), withdraw, "balance of user");
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 0, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, collateralToken);

        vm.prank(borrower);
        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);

        assertEq(morphoV2.collateralOf(id, borrower, collateralToken), initialCollateral - withdraw, "collateral of");
        assertEq(
            ERC20(collateralToken).balanceOf(address(morphoV2)), initialCollateral - withdraw, "balance of morphoV2"
        );
        assertEq(ERC20(collateralToken).balanceOf(borrower), withdraw, "balance of borrower");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, collateralToken);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.prank(borrower);
        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);
    }

    function testRepay(uint256 units, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        units = bound(units, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        skip(99);
        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        morphoV2.repay(obligation, repaid, borrower);

        assertEq(morphoV2.debtOf(id, borrower), units - repaid);
        assertEq(morphoV2.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdrawInconsistentInput(uint256 units, uint256 shares) public {
        vm.assume(units > 0 && shares > 0);
        vm.prank(lender);
        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.withdraw(obligation, units, shares, lender);
    }

    function testWithdrawWithObligations(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);

        vm.prank(lender);
        (uint256 returnedObligationUnits, uint256 returnedShares) = morphoV2.withdraw(obligation, withdraw, 0, lender);

        assertEq(morphoV2.sharesOf(id, lender), units - withdraw, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(morphoV2.totalShares(id), units - withdraw, "totalShares");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
        assertEq(returnedObligationUnits, withdraw, "returned obligation units");
        assertEq(returnedShares, withdraw, "returned shares");
    }

    function testWithdrawWithShares(uint256 units, uint256 shares) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, units);
        testRepay(units, shares);

        // TODO: sharesPrice != 1
        vm.prank(lender);
        (uint256 returnedObligationUnits, uint256 returnedShares) = morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(morphoV2.sharesOf(id, lender), units - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
        assertEq(returnedObligationUnits, shares, "returned obligation units");
        assertEq(returnedShares, shares, "returned shares");
    }

    function testConsume(address user, bytes32 group, uint256 amount) public {
        vm.prank(user);
        morphoV2.consume(group, amount);
        assertEq(morphoV2.consumed(user, group), amount, "consumed");
    }

    function testTouchObligation(Obligation memory _obligation) public {
        _obligation = sortedAndUniqueCollateralsInObligation(_obligation);

        bytes32 _id = morphoV2.touchObligation(_obligation);
        assertEq(morphoV2.obligationCreated(_id), true, "obligation created");
        uint16[6] memory fees = morphoV2.fees(_id);
        for (uint256 i = 0; i < 6; i++) {
            assertEq(fees[i], morphoV2.defaultFees(_obligation.loanToken, i), "fees");
        }
    }

    function testIdToObligation(Obligation memory _obligation) public {
        _obligation = sortedAndUniqueCollateralsInObligation(_obligation);

        bytes32 _id = morphoV2.touchObligation(_obligation);
        Obligation memory obligationFromId = IdLib.idToObligation(_id, address(morphoV2));
        assertEq(_obligation.loanToken, obligationFromId.loanToken, "loanToken");
        assertEq(_obligation.maturity, obligationFromId.maturity, "maturity");
        assertEq(_obligation.collaterals.length, obligationFromId.collaterals.length, "collaterals length");
        for (uint256 i = 0; i < obligationFromId.collaterals.length; i++) {
            assertEq(_obligation.collaterals[i].token, obligationFromId.collaterals[i].token, "collateral token");
            assertEq(_obligation.collaterals[i].lltv, obligationFromId.collaterals[i].lltv, "lltv");
            assertEq(_obligation.collaterals[i].oracle, obligationFromId.collaterals[i].oracle, "oracle");
        }
    }

    function testSstore2CodeStartsWithStop(Obligation memory _obligation) public {
        _obligation = sortedAndUniqueCollateralsInObligation(_obligation);

        bytes32 _id = morphoV2.touchObligation(_obligation);
        address sstore2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(morphoV2), bytes32(0), _id)))));

        assertGt(sstore2Address.code.length, 0, "code should exist");
        assertEq(uint8(sstore2Address.code[0]), 0x00, "first byte should be STOP opcode");
    }

    function testShuffleSession(address user) public {
        vm.prank(user);
        morphoV2.shuffleSession();
        assertEq(morphoV2.session(user), keccak256(abi.encode(0, blockhash(block.number - 1))), "session");
    }
}
