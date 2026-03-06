// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {Obligation, Collateral} from "../src/interfaces/IMidnight.sol";

import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant CONTINUOUS_FEE = 0.01e18; // 1% per second (for testing)
    uint256 internal constant DEBT_AMOUNT = 1e18;

    function setUp() public override {
        super.setUp();

        vm.warp(block.timestamp + 1000 days);

        midnight.setFeeRecipient(feeRecipient);
        midnight.setDefaultContinuousFee(address(loanToken), CONTINUOUS_FEE);

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 365 days;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );

        id = toId(obligation);

        collateralize(obligation, borrower, MAX_TEST_AMOUNT / 2);
        setupObligation(obligation, DEBT_AMOUNT);
    }

    // --- accrueContinuousFee ---

    function testAccrueFeeIncreasesDebt(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);

        uint256 debtBefore = midnight.debtOf(id, borrower);
        uint256 totalUnitsBefore = midnight.totalUnits(id);
        uint256 totalSharesBefore = midnight.totalShares(id);

        vm.warp(block.timestamp + elapsed);

        uint256 expectedFee = debtBefore.mulDivDown(CONTINUOUS_FEE * elapsed, WAD);
        uint256 expectedFeeShares = expectedFee.mulDivDown(totalSharesBefore + 1, totalUnitsBefore + 1);

        vm.expectEmit(true, true, true, true);
        emit EventsLib.AccrueContinuousFee(id, expectedFee);
        midnight.accrueContinuousFee(id, borrower);

        assertEq(midnight.debtOf(id, borrower), debtBefore + expectedFee, "debt should increase by fee");
        assertEq(midnight.totalUnits(id), totalUnitsBefore + expectedFee, "total units should increase by fee");
        assertEq(
            midnight.totalShares(id),
            totalSharesBefore + expectedFeeShares,
            "total shares should increase by fee shares"
        );
        assertEq(midnight.sharesOf(id, feeRecipient), expectedFeeShares, "fee recipient should receive shares");
    }

    function testAccrueFeeZeroContinuousFee(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);

        midnight.setContinuousFee(id, 0);
        uint256 debtBefore = midnight.debtOf(id, borrower);

        vm.warp(block.timestamp + elapsed);
        midnight.accrueContinuousFee(id, borrower);

        assertEq(midnight.debtOf(id, borrower), debtBefore, "debt should not change with zero fee");
    }

    function testAccrueFeeNotCreated(bytes32 fakeId) public {
        (,,, bool created,) = midnight.obligationState(fakeId);
        vm.assume(!created);
        vm.expectRevert("obligation not created");
        midnight.accrueContinuousFee(fakeId, borrower);
    }
}
