// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract PostMaturityLiquidationTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    Seizure[] internal recordedSeizures;
    address internal recordedBorrower;
    address internal recordedLiquidator;
    bytes internal recordedData;

    function setUp() public override {
        super.setUp();

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});
        collaterals = sortCollaterals(collaterals);

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            obligation.collaterals.push(collaterals[i]);
        }
        obligation.chainId = block.chainid;

        id = toId(obligation);
    }

    function testLiquidateBeforeMaturity() public {
        // Setup
        setupObligation(obligation, 100);
        deal(address(loanToken), address(this), 1);

        vm.warp(obligation.maturity - 1);

        vm.expectRevert("post maturity liquidation is after maturity");
        morphoV2.postMaturityLiquidation(obligation, new Seizure[](0), borrower, "");
    }

    function testPostMaturityLiquidateBondsInput() public {
        // Setup
        setupObligation(obligation, 100, 200);
        deal(address(loanToken), address(this), 1);

        vm.warp(obligation.maturity);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 0});
        morphoV2.postMaturityLiquidation(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 199);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateCollateralInput() public {
        // Setup
        setupObligation(obligation, 100, 200);
        deal(address(loanToken), address(this), 1);

        vm.warp(obligation.maturity);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 0, seized: 1});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 0});
        morphoV2.postMaturityLiquidation(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 199);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateTarget() public {
        // Setup
        setupObligation(obligation, 100, 200);
        deal(address(loanToken), address(this), 1);

        vm.warp(obligation.maturity + 15 minutes);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 0});
        morphoV2.postMaturityLiquidation(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 199);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateLate() public {
        // Setup
        setupObligation(obligation, 100, 200);
        deal(address(loanToken), address(this), 1);

        vm.warp(obligation.maturity + 10500);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 0});
        morphoV2.postMaturityLiquidation(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 39);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 195);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }
}
