// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {console} from "forge-std/Test.sol";
import {TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";

contract TickLibTest is BaseTest {
    using UtilsLib for uint256;

    // Tick to price

    function testTickToPriceMinMax() public pure {
        assertEq(TickLib.tickToPrice(0), 0, "tick 0");
        assertEq(TickLib.tickToPrice(2), 1e12, "first non-zero tick");
        assertEq(TickLib.tickToPrice(MAX_TICK - 2), 1e18 - 1e12, "tick max - 2 just below par");
        assertEq(TickLib.tickToPrice(MAX_TICK), 1e18, "tick max");
    }

    function expR(int256 r) internal pure returns (int256) {
        int256 secondTerm = r * r / (2 * 1e18);
        int256 thirdTerm = secondTerm * r / (3 * 1e18);
        return 1e18 + r + secondTerm + thirdTerm;
    }

    function testWExpOffsetProperty() public pure {
        int256 ln2 = 0.693147180559945309e18;
        int256 offset = 0.32261121498945987e18;
        assertEq(2 * expR(-offset), expR(ln2 - offset - 1));
    }

    function testTickMonotonicity() public pure {
        for (uint256 i = 0; i < MAX_TICK; i++) {
            assertGe(TickLib.tickToPrice(i + 1), TickLib.tickToPrice(i));
        }
    }

    function testReturnJumps() public pure {
        for (uint256 i = 1400; i <= 4600; i++) {
            uint256 previousReturn = _return(TickLib.tickToPrice(i - 1));
            uint256 currentReturn = _return(TickLib.tickToPrice(i));
            assertApproxEqRel(
                currentReturn.mulDivDown(1e18, previousReturn),
                0.995e18,
                0.005e18,
                string.concat("tick ", vm.toString(i))
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
        tick = bound(tick, 0, MAX_TICK);
        TickLib.tickToPrice(tick);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testTickToPriceOutOfRange(uint256 tick) public {
        tick = bound(tick, MAX_TICK + 1, type(uint256).max);
        vm.expectRevert(TickLib.TickOutOfRange.selector);
        TickLib.tickToPrice(tick);
    }

    // Price to tick

    /// forge-config: default.allow_internal_expect_revert = true
    function testPriceToTickGreaterThanOne(uint256 price) public {
        price = bound(price, 1 ether + 1, type(uint256).max);
        vm.expectRevert(TickLib.PriceGreaterThanOne.selector);
        TickLib.priceToTick(price, 1);
    }

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        uint256 tick = TickLib.priceToTick(price, 1);
        assertGe(TickLib.tickToPrice(tick), price);
        if (tick > 0) assertLe(TickLib.tickToPrice(tick - 1), price);
    }

    function testPriceToTickConsistency() public pure {
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            uint256 price = TickLib.tickToPrice(tick);
            uint256 recoveredTick = TickLib.priceToTick(price, 1);
            assertEq(TickLib.tickToPrice(recoveredTick), price);
            assertLe(recoveredTick, tick);
        }
    }

    function testGasPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        TickLib.priceToTick(price, 1);
    }

    function loadExactPrices() internal view returns (uint256[] memory) {
        uint256[] memory exactPrices = new uint256[](MAX_TICK + 1);
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

        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            uint256 solPrice = TickLib.tickToPrice(tick);
            uint256 exactPrice = exactPrices[tick];

            uint256 absErrorWad = absDiff(solPrice, exactPrice);
            maxAbsErrorWad = max(maxAbsErrorWad, absErrorWad);
            totalAbsErrorWad += absErrorWad;
            uint256 relErrorWad = absDiff(solPrice, exactPrice) * 1e18 / exactPrice;
            totalRelErrorWad += relErrorWad;
            maxRelErrorWad = max(maxRelErrorWad, relErrorWad);

            // 3-term Taylor in wExp yields max ~1.4 bps absolute error; 2 bps threshold leaves headroom.
            assertLe(absErrorWad, 0.00014e18, string.concat("Tick ", vm.toString(tick), " error exceeds 2 bps"));
            if (solPrice > 0.01e18) {
                assertLe(relErrorWad, 0.0007e18, string.concat("Tick ", vm.toString(tick), " error exceeds 7 bps"));
            }

            // Check exact price is bracketed by adjacent sol prices in the bulk of the range,
            // away from the rounding-dominated tails.
            if (solPrice > 0.01e18 && solPrice < 0.99e18) {
                assertGe(
                    exactPrice,
                    TickLib.tickToPrice(tick - 1),
                    string.concat("Tick ", vm.toString(tick), " exact < prev sol")
                );
                assertLe(
                    exactPrice,
                    TickLib.tickToPrice(tick + 1),
                    string.concat("Tick ", vm.toString(tick), " exact > next sol")
                );
            }
        }

        console.log("Max absolute error (wad):", maxAbsErrorWad);
        console.log("Avg absolute error (wad):", totalAbsErrorWad / (MAX_TICK + 1));
        console.log("Max relative error (wad):", maxRelErrorWad);
        console.log("Avg relative error (wad):", totalRelErrorWad / (MAX_TICK + 1));
    }
}
