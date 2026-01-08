// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {Matching, WAD, MIN_TICK, MAX_TICK} from "../src/Matching.sol";
import {Offer, Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

contract MatchingTest is Test {
    Matching public matching;

    function setUp() public {
        matching = new Matching();
        console.log("Deployed code size:", address(matching).code.length);
    }

    /// @notice Verifies TABLE_OFFSET constant matches actual table location in bytecode.
    /// @dev Searches for PUSH9 + 0x01075ddfff19d43446 (encoded value at index 5) which is
    ///      50 bytes from the table base. Fails if constant doesn't match.
    function testTableOffset() public view {
        bytes memory code = address(matching).code;
        uint256 foundOffset;
        bool found;

        // Search for PUSH9 (0x68) + 0x01075ddfff19d43446
        // Index 5 is at position 50 bytes from table base (5 values * 10 bytes each)
        // forgefmt: disable-start
        for (uint256 i = 0; i < code.length - 10; i++) {
            if (code[i] == 0x68 &&
                code[i+1] == 0x01 &&
                code[i+2] == 0x07 &&
                code[i+3] == 0x5d &&
                code[i+4] == 0xdf &&
                code[i+5] == 0xff &&
                code[i+6] == 0x19 &&
                code[i+7] == 0xd4 &&
                code[i+8] == 0x34 &&
                code[i+9] == 0x46) {
                foundOffset = i - 50;  // index 5 is 50 bytes after base
                found = true;
                break;
            }
        }
        // forgefmt: disable-end

        assertTrue(found, "Table pattern not found in bytecode");
        assertEq(matching.TABLE_OFFSET(), foundOffset, "TABLE_OFFSET constant does not match actual table location");
    }

    function testTickToPrice() public view {
        uint256 price0 = matching.tickToPrice(0);
        // console.log("Price at tick 0:", price0);
        assertEq(price0, WAD / 2); // 0.5 WAD

        uint256 priceNeg1 = matching.tickToPrice(-1);
        console.log("Price at tick -1:", priceNeg1);

        uint256 pricePos1 = matching.tickToPrice(1);
        console.log("Price at tick 1:", pricePos1);
        assertEq(pricePos1, WAD - priceNeg1); // symmetry check
    }

    function testPriceToTick() public view {
        // Test round-trip for various ticks
        for (int256 tick = -100; tick <= 100; tick += 10) {
            uint256 price = matching.tickToPrice(tick);
            int256 recovered = matching.priceToTick(price, MIN_TICK, MAX_TICK);
            int256 diff = tick - recovered;
            if (diff < 0) diff = -diff;
            assertLe(uint256(diff), 1, "priceToTick off by more than 1");
        }
    }

    function testExtremeTicks() public view {
        uint256 priceMin = matching.tickToPrice(-1679);
        console.log("Price at tick -1679:", priceMin);

        uint256 priceMax = matching.tickToPrice(1679);
        console.log("Price at tick 1679:", priceMax);
    }

    function testGas() public view {
        // tickToPrice gas (negative tick)
        matching.tickToPrice(-500);

        // tickToPrice gas (positive tick)
        matching.tickToPrice(500);

        // priceToTick gas (full range search)
        uint256 price = matching.tickToPrice(-500);
        matching.priceToTick(price, MIN_TICK, MAX_TICK);

        // priceToTick gas (narrow range search)
        matching.priceToTick(price, -600, -400);
    }
}
