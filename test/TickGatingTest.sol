// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMidnight, Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK, BASE_SPACING} from "../src/libraries/TickLib.sol";

import {BaseTest} from "./BaseTest.sol";

/// @dev Integration tests for tick spacing enforcement in take() and spacing governance.
contract TickGatingTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);

        // Create the obligation so it picks up spacing 4.
        id = midnight.touchObligation(obligation);
    }

    function _makeOffer(uint256 tick) internal view returns (Offer memory offer) {
        offer.obligation = obligation;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(ecrecoverRatifier);
        offer.maxUnits = type(uint256).max;
        offer.expiry = block.timestamp + 200;
        offer.tick = tick;
    }

    // --- Default spacing applied at creation ---

    function testDefaultSpacingApplied() public view {
        assertEq(midnight.spacing(id), 4, "obligation should inherit default spacing 4");
    }

    // --- Tick gating in take() ---

    function testTakeSucceedsAtAccessibleTick() public {
        uint256 tick = MAX_TICK; // Always accessible.
        Offer memory offer = _makeOffer(tick);
        uint256 units = 100;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer);
        assertEq(midnight.creditOf(id, lender), units);
    }

    function testTakeRevertsAtInaccessibleTick() public {
        // Tick 2921 is not divisible by 4 → inaccessible at spacing 4.
        Offer memory offer = _makeOffer(2921);
        uint256 units = 100;
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        vm.expectRevert(IMidnight.TickNotAccessible.selector);
        midnight.take(units, borrower, address(0), hex"", borrower, offer, merkleRatifierData([offer]));
    }

    function testTakeRevertsAtSpacing2InaccessibleTick() public {
        // Refine to spacing 2.
        midnight.setObligationSpacing(id, 2);

        // Tick 2921 is not divisible by 2 → inaccessible at spacing 2.
        Offer memory offer = _makeOffer(2921);
        uint256 units = 100;
        deal(address(loanToken), lender, type(uint128).max);
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        vm.expectRevert(IMidnight.TickNotAccessible.selector);
        midnight.take(units, borrower, address(0), hex"", borrower, offer, merkleRatifierData([offer]));
    }

    // --- Spacing refinement enables previously inaccessible ticks ---

    function testRefineMakesPreviouslyInaccessibleTickValid() public {
        // Tick 2922: not accessible at spacing 4, but accessible at spacing 2.
        uint256 tick = 2922;
        Offer memory offer = _makeOffer(tick);
        uint256 units = 100;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);

        // Should fail at spacing 4.
        vm.prank(borrower);
        vm.expectRevert(IMidnight.TickNotAccessible.selector);
        midnight.take(units, borrower, address(0), hex"", borrower, offer, merkleRatifierData([offer]));

        // Refine to spacing 2.
        midnight.setObligationSpacing(id, 2);

        // Now should succeed.
        take(units, borrower, offer);
        assertEq(midnight.creditOf(id, lender), units);
    }

    // --- setObligationSpacing governance ---

    function testSetObligationSpacingOnlySpacingSetter() public {
        vm.prank(lender);
        vm.expectRevert(IMidnight.OnlySpacingSetter.selector);
        midnight.setObligationSpacing(id, 2);
    }

    function testSetObligationSpacingInvalid() public {
        vm.expectRevert(IMidnight.InvalidSpacing.selector);
        midnight.setObligationSpacing(id, 3);

        vm.expectRevert(IMidnight.InvalidSpacing.selector);
        midnight.setObligationSpacing(id, 0);

        midnight.setObligationSpacing(id, 1);
        vm.expectRevert(IMidnight.InvalidSpacing.selector);
        midnight.setObligationSpacing(id, 2);
    }

    function testSetObligationSpacingRequiresCreated() public {
        vm.expectRevert(IMidnight.ObligationNotCreated.selector);
        midnight.setObligationSpacing(bytes32(uint256(42)), 1);
    }

    // --- setSpacingSetter governance ---

    function testSetSpacingSetterOnlyOwner() public {
        vm.prank(lender);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
        midnight.setSpacingSetter(lender);
    }

    // --- Coarser ticks remain valid after refinement ---

    function testCoarserTicksStillValidAfterRefinement() public {
        // Tick 2924: accessible at spacing 4. Trade at spacing 4.
        uint256 tick = 2924;
        Offer memory offer = _makeOffer(tick);
        uint256 units = 50;
        uint256 price = TickLib.tickToPrice(tick);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer);

        // Refine to spacing 1 (every tick).
        midnight.setObligationSpacing(id, 1);

        // Tick 2924 is still accessible at spacing 1.
        Offer memory offer2 = _makeOffer(tick);
        offer2.group = keccak256("second");
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));
        collateralize(obligation, borrower, units);
        take(units, borrower, offer2);

        assertEq(midnight.creditOf(id, lender), 2 * units);
    }
}
