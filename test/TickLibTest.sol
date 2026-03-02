// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {console} from "forge-std/Test.sol";
import {TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";

contract TickLibTest is BaseTest {
    using UtilsLib for uint256;

    // Tick to price

    function testTickToPriceMinMax() public pure {
        assertEq(TickLib.tickToPrice(0), 0, "tick 0");
        assertEq(TickLib.tickToPrice(1), 1e13, "tick 1");
        assertEq(TickLib.tickToPrice(TICK_RANGE - 1), 0.99999e18, "tick max - 1");
        assertEq(TickLib.tickToPrice(TICK_RANGE), 1e18, "tick max");
    }

    function testTickMonotonicity() public pure {
        for (uint256 i = 0; i < TICK_RANGE; i++) {
            assertGe(TickLib.tickToPrice(i + 1), TickLib.tickToPrice(i));
        }
    }

    function testTickToPriceRange() public pure {
        for (uint256 i = 0; i <= TICK_RANGE; i++) {
            console.log(TickLib.tickToPrice(i));
        }
    }

    function testReturnJumps() public pure {
        for (uint256 i = 207; i <= 729; i++) {
            uint256 previousReturn = _return(TickLib.tickToPrice(i - 1));
            uint256 currentReturn = _return(TickLib.tickToPrice(i));
            assertApproxEqRel(
                currentReturn.mulDivDown(1e18, previousReturn), 1.025e18, 0.1e18, string.concat("tick ", vm.toString(i))
            );
        }
    }

    function _return(uint256 price) internal pure returns (uint256) {
        return uint256(1e18).mulDivDown(1e18, price) - 1e18;
    }

    // To be able to subtract the gas used by bound.
    function testGasBound(uint256 value) public pure {
        bound(value, 0, 1 ether);
    }

    function testGasTickToPrice(uint256 tick) public pure {
        tick = bound(tick, 0, TICK_RANGE);
        TickLib.tickToPrice(tick);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testTickToPriceOutOfRange(uint256 tick) public {
        tick = bound(tick, TICK_RANGE + 1, type(uint256).max);
        vm.expectRevert("tick out of range");
        TickLib.tickToPrice(tick);
    }

    // Price to tick

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        uint256 tick = TickLib.priceToTick(price);
        assertGe(TickLib.tickToPrice(tick), price);
        if (tick > 0) assertLe(TickLib.tickToPrice(tick - 1), price);
    }

    function testPriceToTickConsistency() public pure {
        for (uint256 tick = 0; tick <= TICK_RANGE; tick++) {
            uint256 price = TickLib.tickToPrice(tick);
            uint256 recoveredTick = TickLib.priceToTick(price);
            assertEq(TickLib.tickToPrice(recoveredTick), price);
            assertLe(recoveredTick, tick);
        }
    }

    function testGasPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        TickLib.priceToTick(price);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testPriceToTickPriceGreaterThanOne(uint256 price) public {
        price = bound(price, 1e18 + 1, type(uint256).max);
        vm.expectRevert("Price is greater than one");
        TickLib.priceToTick(price);
    }

    function loadExactPrices() internal view returns (uint256[] memory) {
        uint256[] memory exactPrices = new uint256[](TICK_RANGE + 1);
        string memory json = vm.readFile("test/ticks_exact.json");
        string[] memory priceStrings = vm.parseJsonStringArray(json, ".prices");
        for (uint256 i = 0; i < priceStrings.length; i++) {
            exactPrices[i] = vm.parseUint(priceStrings[i]);
        }
        return exactPrices;
    }

    function testTickToPriceAccuracy() public view {
        uint256[] memory exactPrices = loadExactPrices();
        uint256 maxAbsErrorWad;
        uint256 maxRelErrorWad;
        uint256 totalAbsErrorWad;
        uint256 totalRelErrorWad;

        for (uint256 tick = 0; tick <= TICK_RANGE; tick++) {
            uint256 solPrice = TickLib.tickToPrice(tick);
            uint256 exactPrice = exactPrices[tick];

            uint256 absErrorWad = absDiff(solPrice, exactPrice);
            maxAbsErrorWad = max(maxAbsErrorWad, absErrorWad);
            totalAbsErrorWad += absErrorWad;
            uint256 relErrorWad = absDiff(solPrice, exactPrice) * 1e18 / exactPrice;
            totalRelErrorWad += relErrorWad;
            maxRelErrorWad = max(maxRelErrorWad, relErrorWad);

            assertLe(absErrorWad, 0.00015e18, string.concat("Tick ", vm.toString(tick), " error exceeds 1.5 bps"));
            if (solPrice > 0.01e18) {
                assertLe(relErrorWad, 0.001e18, string.concat("Tick ", vm.toString(tick), " error exceeds 0.1%"));
            }

            // Check exact price is bracketed by adjacent sol prices (only where prices vary per-tick)
            if (tick > 0 && tick < TICK_RANGE) {
                uint256 prevSolPrice = TickLib.tickToPrice(tick - 1);
                uint256 nextSolPrice = TickLib.tickToPrice(tick + 1);
                if (prevSolPrice < solPrice && solPrice < nextSolPrice) {
                    assertGe(exactPrice, prevSolPrice, string.concat("Tick ", vm.toString(tick), " exact < prev sol"));
                    assertLe(exactPrice, nextSolPrice, string.concat("Tick ", vm.toString(tick), " exact > next sol"));
                }
            }
        }

        console.log("Max absolute error (wad):", maxAbsErrorWad);
        console.log("Avg absolute error (wad):", totalAbsErrorWad / TICK_RANGE);
        console.log("Max relative error (wad):", maxRelErrorWad);
        console.log("Avg relative error (wad):", totalRelErrorWad / TICK_RANGE);
    }
}
