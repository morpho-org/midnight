// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {console} from "forge-std/Test.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract TickLibTest is BaseTest {
    using UtilsLib for uint256;

    function testSomeTicks() public pure {
        assertEq(TickLib.tickToPrice(0), 0);
        assertEq(TickLib.tickToPrice(MAX_TICK / 2), 1e18 / 2);
        assertEq(TickLib.tickToPrice(MAX_TICK), 1e18);
    }

    function testSomePrices() public pure {
        uint256 t = TickLib.priceToTick(0);
        assertEq(t, 0);
        assertEq(TickLib.tickToPrice(t), 0);
        t = TickLib.priceToTick(1e18 / 2);
        assertEq(t, MAX_TICK / 2);
        assertEq(TickLib.tickToPrice(t), 1e18 / 2);
        t = TickLib.priceToTick(1e18);
        assertEq(t, MAX_TICK);
        assertEq(TickLib.tickToPrice(t), 1e18);
    }

    function testTickToPriceMonotone() public pure {
        for (uint256 t = 0; t < MAX_TICK; t++) {
            assertLe(TickLib.tickToPrice(t), TickLib.tickToPrice(t + 1), "price should be monotonically increasing");
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

    function testPriceToTick() public pure {
        // When exactly between 2 prices match the higher one.
        for (uint256 tick = 0; tick <= MAX_TICK; tick++) {
            uint256 price = TickLib.tickToPrice(tick);
            if (tick < MAX_TICK) {
                uint256 nextPrice = TickLib.tickToPrice(tick + 1);
                if (price != nextPrice) {
                    uint256 edgePrice = price + (nextPrice - price - 1) / 2;
                    assertEq(
                        TickLib.tickToPrice(TickLib.priceToTick(edgePrice)), price, "lower price up to same distance"
                    );
                }
            }
            if (tick > 0) {
                uint256 prevPrice = TickLib.tickToPrice(tick - 1);
                if (price != prevPrice) {
                    uint256 edgePrice = price - (price - prevPrice) / 2;
                    assertEq(TickLib.tickToPrice(TickLib.priceToTick(edgePrice)), price, "higher price not matching");
                }
            }
        }
    }

    function testGasPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        TickLib.priceToTick(price);
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

            assertLe(absErrorWad, 0.00015e18, string.concat("Tick ", vm.toString(tick), " error exceeds 1.5 bps"));
            if (solPrice > 0.01e18) {
                assertLe(relErrorWad, 0.001e18, string.concat("Tick ", vm.toString(tick), " error exceeds 0.1%"));
            }

            // Check exact price is bracketed by adjacent sol prices (only where prices vary per-tick)
            if (tick > 0 && tick < MAX_TICK) {
                uint256 prevSolPrice = TickLib.tickToPrice(tick - 1);
                uint256 nextSolPrice = TickLib.tickToPrice(tick + 1);
                if (prevSolPrice < solPrice && solPrice < nextSolPrice) {
                    assertGe(exactPrice, prevSolPrice, string.concat("Tick ", vm.toString(tick), " exact < prev sol"));
                    assertLe(exactPrice, nextSolPrice, string.concat("Tick ", vm.toString(tick), " exact > next sol"));
                }
            }
        }

        console.log("Max absolute error (wad):", maxAbsErrorWad);
        console.log("Avg absolute error (wad):", totalAbsErrorWad / MAX_TICK);
        console.log("Max relative error (wad):", maxRelErrorWad);
        console.log("Avg relative error (wad):", totalRelErrorWad / MAX_TICK);
    }
}
