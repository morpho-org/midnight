// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {MAX_LEVEL} from "../src/libraries/AccessibleTickLib.sol";

import {BaseTest} from "./BaseTest.sol";

/// @dev Integration tests for tick accessibility enforcement in take() and tick level governance.
contract TickGatingTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals.push(
            Collateral({
                token: address(collateralToken1),
                lltv: 0.77e18,
                maxLif: maxLif(0.77e18, 0.25e18),
                oracle: address(oracle1)
            })
        );
        obligation.collaterals.push(
            Collateral({
                token: address(collateralToken2),
                lltv: 0.77e18,
                maxLif: maxLif(0.77e18, 0.25e18),
                oracle: address(oracle2)
            })
        );
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        // Set default tick level to 0 (most restrictive) for this test's loan token.
        midnight.setDefaultTickLevel(address(loanToken), 0);

        // Create the obligation so it picks up level 0.
        id = midnight.touchObligation(obligation);
    }

    function _makeOffer(uint256 tick) internal view returns (Offer memory offer) {
        offer.obligation = obligation;
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = type(uint256).max;
        offer.expiry = block.timestamp + 200;
        offer.tick = tick;
    }

    // --- Default tick level applied at creation ---

    function testDefaultTickLevelApplied() public view {
        assertEq(midnight.tickLevel(id), 0, "obligation should inherit default level 0");
    }

    // --- Tick gating in take() ---

    function testTakeSucceedsAtAccessibleTick() public {
        uint256 tick = 2600; // MAX_TICK, divisible by 8 → accessible at level 0.
        Offer memory offer = _makeOffer(tick);
        uint256 units = 100;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer);
        assertEq(midnight.creditOf(id, lender), units);
    }

    function testTakeRevertsAtInaccessibleTick() public {
        // Tick 4 is not divisible by 8 → inaccessible at level 0.
        Offer memory offer = _makeOffer(4);
        uint256 units = 100;
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        vm.expectRevert("tick not accessible at obligation level");
        midnight.take(
            units, borrower, address(0), hex"", borrower, offer, sig([offer]), root([offer]), proof([offer])
        );
    }

    function testTakeRevertsAtLevel1InaccessibleTick() public {
        // Upgrade to level 1 (every 4th tick).
        midnight.setObligationTickLevel(id, 1);

        // Tick 6 is divisible by 2 but not by 4 → inaccessible at level 1.
        Offer memory offer = _makeOffer(6);
        uint256 units = 100;
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        vm.expectRevert("tick not accessible at obligation level");
        midnight.take(
            units, borrower, address(0), hex"", borrower, offer, sig([offer]), root([offer]), proof([offer])
        );
    }

    // --- Level upgrade enables previously inaccessible ticks ---

    function testUpgradeMakesPreviouslyInaccessibleTickValid() public {
        // Tick 4: not accessible at level 0 (needs ÷8), but accessible at level 1 (÷4).
        uint256 tick = 4;
        Offer memory offer = _makeOffer(tick);
        uint256 units = 100;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);

        // Should fail at level 0.
        vm.prank(borrower);
        vm.expectRevert("tick not accessible at obligation level");
        midnight.take(
            units, borrower, address(0), hex"", borrower, offer, sig([offer]), root([offer]), proof([offer])
        );

        // Upgrade to level 1.
        midnight.setObligationTickLevel(id, 1);

        // Now should succeed.
        take(units, borrower, offer);
        assertEq(midnight.creditOf(id, lender), units);
    }

    // --- setObligationTickLevel governance ---

    function testSetObligationTickLevelOnlyTickSetter() public {
        vm.prank(lender);
        vm.expectRevert("only tick setter");
        midnight.setObligationTickLevel(id, 1);
    }

    function testSetObligationTickLevelCanOnlyIncrease() public {
        midnight.setObligationTickLevel(id, 2);

        vm.expectRevert("can only increase tick level");
        midnight.setObligationTickLevel(id, 2);

        vm.expectRevert("can only increase tick level");
        midnight.setObligationTickLevel(id, 1);
    }

    function testSetObligationTickLevelOutOfRange() public {
        vm.expectRevert("level out of range");
        midnight.setObligationTickLevel(id, MAX_LEVEL + 1);
    }

    function testSetObligationTickLevelRequiresCreated() public {
        vm.expectRevert("obligation not created");
        midnight.setObligationTickLevel(bytes32(uint256(42)), 1);
    }

    // --- setDefaultTickLevel governance ---

    function testSetDefaultTickLevelOnlyTickSetter() public {
        vm.prank(lender);
        vm.expectRevert("only tick setter");
        midnight.setDefaultTickLevel(address(loanToken), 1);
    }

    function testSetDefaultTickLevelOutOfRange() public {
        vm.expectRevert("level out of range");
        midnight.setDefaultTickLevel(address(loanToken), MAX_LEVEL + 1);
    }

    function testSetDefaultTickLevelCanDecrease() public {
        midnight.setDefaultTickLevel(address(loanToken), 3);
        midnight.setDefaultTickLevel(address(loanToken), 1);
        assertEq(midnight.defaultTickLevel(address(loanToken)), 1);
    }

    // --- setTickSetter governance ---

    function testSetTickSetterOnlyOwner() public {
        vm.prank(lender);
        vm.expectRevert("only owner");
        midnight.setTickSetter(lender);
    }

    // --- Coarser ticks remain valid after upgrade ---

    function testCoarserTicksStillValidAfterUpgrade() public {
        // Tick 8: accessible at level 0. Trade at level 0.
        uint256 tick = 8;
        Offer memory offer = _makeOffer(tick);
        uint256 units = 50;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer);

        // Upgrade to level 3 (every tick).
        midnight.setObligationTickLevel(id, 3);

        // Tick 8 is still accessible at level 3 (monotonic refinement).
        Offer memory offer2 = _makeOffer(tick);
        offer2.group = keccak256("second");
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer2);

        assertEq(midnight.creditOf(id, lender), 2 * units);
    }
}
