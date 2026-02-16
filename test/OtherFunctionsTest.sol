// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IdLib} from "../src/libraries/IdLib.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {RevertingOracle} from "./helpers/RevertingOracle.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
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
        obligation.minCollatValue = 0;

        id = toId(obligation);
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
        morphoV2.supplyCollateral(obligation, 0, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, collateralToken);

        vm.prank(borrower);
        morphoV2.withdrawCollateral(obligation, 0, withdraw, borrower, borrower);

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
        morphoV2.supplyCollateral(obligation, 0, additionalCollateral, borrower);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, collateralToken);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.prank(borrower);
        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, 0, withdraw, borrower, borrower);
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
        morphoV2.withdraw(obligation, units, shares, lender, lender);
    }

    function testWithdrawWithObligations(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);

        vm.prank(lender);
        (uint256 returnedObligationUnits, uint256 returnedShares) =
            morphoV2.withdraw(obligation, withdraw, 0, lender, lender);

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
        (uint256 returnedObligationUnits, uint256 returnedShares) =
            morphoV2.withdraw(obligation, 0, shares, lender, lender);

        assertEq(morphoV2.sharesOf(id, lender), units - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
        assertEq(returnedObligationUnits, shares, "returned obligation units");
        assertEq(returnedShares, shares, "returned shares");
    }

    function testWithdrawToReceiver(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);
        address receiver = makeAddr("receiver");

        vm.prank(lender);
        morphoV2.withdraw(obligation, withdraw, 0, lender, receiver);

        assertEq(loanToken.balanceOf(lender), 0, "balance of lender");
        assertEq(loanToken.balanceOf(receiver), withdraw, "balance of receiver");
    }

    function testWithdrawCollateralToReceiver(uint256 supply, uint256 withdraw) public {
        supply = bound(supply, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, supply);
        address collateralToken = obligation.collaterals[0].token;
        address receiver = makeAddr("receiver");
        deal(collateralToken, address(this), supply);
        ERC20(collateralToken).approve(address(morphoV2), supply);
        morphoV2.supplyCollateral(obligation, 0, supply, address(this));

        morphoV2.withdrawCollateral(obligation, 0, withdraw, address(this), receiver);

        assertEq(ERC20(collateralToken).balanceOf(address(this)), 0, "balance of this");
        assertEq(ERC20(collateralToken).balanceOf(receiver), withdraw, "balance of receiver");
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

    function testMinCollatValueInSupplyCollateral(uint256 collateral, uint256 price, uint256 minCollatValue) public {
        collateral = bound(collateral, 1, MAX_TEST_AMOUNT);
        price = bound(price, 1, ORACLE_PRICE_SCALE);
        Oracle(obligation.collaterals[0].oracle).setPrice(price);

        uint256 collateralValue = collateral.mulDivDown(price, ORACLE_PRICE_SCALE);
        minCollatValue = bound(minCollatValue, collateralValue + 1, type(uint256).max);
        obligation.minCollatValue = minCollatValue;

        address collateralToken = obligation.collaterals[0].token;
        deal(collateralToken, address(this), collateral);
        ERC20(collateralToken).approve(address(morphoV2), collateral);
        vm.expectRevert("Below min collateral");
        morphoV2.supplyCollateral(obligation, 0, collateral, borrower);
    }

    function testMinCollatValueInWithdrawCollateral(
        uint256 collateral,
        uint256 price,
        uint256 withdrawnCollateral,
        uint256 minCollatValue
    ) public {
        collateral = bound(collateral, 2, MAX_TEST_AMOUNT);
        price = bound(price, 1, ORACLE_PRICE_SCALE);
        Oracle(obligation.collaterals[0].oracle).setPrice(price);

        uint256 initialValue = collateral.mulDivDown(price, ORACLE_PRICE_SCALE);
        vm.assume(initialValue > 0);

        // withdrawnCollateral must leave some remaining (can't withdraw all)
        withdrawnCollateral = bound(withdrawnCollateral, 1, collateral - 1);
        uint256 remainingValue = (collateral - withdrawnCollateral).mulDivDown(price, ORACLE_PRICE_SCALE);

        // minCollatValue must be in (remainingValue, initialValue] for supply to succeed and withdraw to fail
        vm.assume(remainingValue < initialValue);
        minCollatValue = bound(minCollatValue, remainingValue + 1, initialValue);
        obligation.minCollatValue = minCollatValue;

        address collateralToken = obligation.collaterals[0].token;
        deal(collateralToken, address(this), collateral);
        ERC20(collateralToken).approve(address(morphoV2), collateral);
        morphoV2.supplyCollateral(obligation, 0, collateral, borrower);

        vm.prank(borrower);
        vm.expectRevert("Below min collateral");
        morphoV2.withdrawCollateral(obligation, 0, withdrawnCollateral, borrower, borrower);
    }

    function testSupplyCollateralZeroDoesNotCallOracle() public {
        RevertingOracle revertingOracle = new RevertingOracle();
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(revertingOracle)});

        Obligation memory obligationWithRevertingOracle;
        obligationWithRevertingOracle.loanToken = address(loanToken);
        obligationWithRevertingOracle.maturity = block.timestamp + 100;
        obligationWithRevertingOracle.collaterals = collaterals;

        // Make the oracle revert.
        revertingOracle.stopOracle();

        // Should succeed if oracle is not called.
        morphoV2.supplyCollateral(obligationWithRevertingOracle, 0, 0, borrower);

        vm.expectRevert("Oracle should not be called");
        morphoV2.supplyCollateral(obligationWithRevertingOracle, 0, 1, borrower);
    }

    function testWithdrawCollateralToZeroDoesNotCallOracle(uint256 collateral) public {
        collateral = bound(collateral, 1, MAX_TEST_AMOUNT);

        RevertingOracle revertingOracle = new RevertingOracle();
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(revertingOracle)});

        Obligation memory obligationWithRevertingOracle;
        obligationWithRevertingOracle.loanToken = address(loanToken);
        obligationWithRevertingOracle.maturity = block.timestamp + 100;
        obligationWithRevertingOracle.collaterals = collaterals;

        deal(address(collateralToken1), address(this), collateral);
        morphoV2.supplyCollateral(obligationWithRevertingOracle, 0, collateral, borrower);

        bytes32 _id = toId(obligationWithRevertingOracle);
        assertEq(
            morphoV2.collateralOf(_id, borrower, address(collateralToken1)), collateral, "collateral should be set"
        );

        revertingOracle.stopOracle();

        vm.prank(borrower);
        morphoV2.withdrawCollateral(obligationWithRevertingOracle, 0, collateral, borrower, borrower);

        assertEq(
            morphoV2.collateralOf(_id, borrower, address(collateralToken1)),
            0,
            "collateral should be 0 after withdrawal"
        );
    }
}
