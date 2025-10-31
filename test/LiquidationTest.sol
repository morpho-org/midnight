// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_LIF, TIME_TO_MAX_LIF} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";

import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest} from "./BaseTest.sol";

import "forge-std/console.sol";

contract LiquidationTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    Seizure[] internal recordedSeizures;
    address internal recordedBorrower;
    address internal recordedLiquidator;
    bytes internal recordedData;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testLiquidateHealthyPreMaturity() public {
        setupObligation(obligation, 100);

        vm.expectRevert("position is not liquidatable");
        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPreMaturity() public {
        setupObligation(obligation, 100);
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateHealthyPostMaturity() public {
        setupObligation(obligation, 100);
        obligation.maturity = block.timestamp - 1;

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPostMaturity() public {
        setupObligation(obligation, 100);
        obligation.maturity = block.timestamp - 1;
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateNoOp() public {
        setupObligation(obligation, 100);
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateInconsistentInput() public {
        setupObligation(obligation, 100);
        oracle.setPrice(0);

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 1});

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateObligationUnitsInput() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 133);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 0, seized: 1});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(loanToken.balanceOf(address(this)), 0);
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 133);
    }

    function testLiquidateBadDebt() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(0.5e36);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 132);
        // TODO assert bad debt
    }

    function testLiquidateCallback(bytes memory data) public {
        vm.assume(data.length > 0);

        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, data);

        assertEq(recordedSeizures.length, 1, "seizures length");
        assertEq(recordedSeizures[0].repaid, 1, "repaid obligations");
        assertEq(recordedSeizures[0].seized, 1, "seized assets");
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    // Check that if there is bad debt it is possible to seize all assets.
    function testLiquidateAllWhenBadDebt() public {
        Oracle oracle2 = new Oracle();
        obligation.collaterals[1].oracle = address(oracle2);
        id = toId(obligation);

        setupMaxObligationWithCollaterals(obligation, 100, 100);
        uint256 price = 1e36 * 1e18 / MAX_LIF * 95 / 100;
        uint256 price2 = 1e36 * 1e18 / MAX_LIF;
        oracle.setPrice(price);
        oracle2.setPrice(price2);
        deal(address(loanToken), address(this), 100e18);

        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 0, seized: 100});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 100});

        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) public {
        for (uint256 i = 0; i < seizures.length; i++) {
            recordedSeizures.push(seizures[i]);
        }
        recordedBorrower = borrower;
        recordedLiquidator = liquidator;
        recordedData = data;
    }

    // post maturity liquidation

    function testLiquidatePostMaturityFullLIF(uint256 delay) public {
        delay = bound(delay, 0, 100 weeks);

        setupObligation(obligation, 100);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF + delay);
        deal(address(loanToken), address(this), 100);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 100, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(borrower, id), 0, "debt");
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - 100 * MAX_LIF / 1e18,
            "collateral"
        );
    }

    function testLiquidatePostMaturityPartialLIF(uint256 delay) public {
        delay = bound(delay, 1, TIME_TO_MAX_LIF);

        setupObligation(obligation, 100);
        vm.warp(obligation.maturity + delay);
        deal(address(loanToken), address(this), 100);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token);

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 100, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");

        uint256 lif = 1e18 + (MAX_LIF - 1e18) * delay / TIME_TO_MAX_LIF;

        assertEq(morphoV2.debtOf(borrower, id), 0, "debt");
        assertEq(
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            initialCollateral - 100 * lif / 1e18,
            "collateral"
        );
    }
}
