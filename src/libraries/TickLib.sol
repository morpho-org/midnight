// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD} from "./ConstantsLib.sol";

uint256 constant MAX_TICK = 990;
uint256 constant PRICE_STEP = 1e13;

library TickLib {
    // 1e5 scaled deltas to price 0.5 for tick 495 to 990.
    // Rounded from 1/(1+1.025^(495-tick)), but they can be shifted to keep the map injective.
    // To generate the map: https://gist.github.com/d67bcf5c3f62e5d734f7745c95e11407
    bytes internal constant PACKED_DELTAS = hex"0000" hex"0269" hex"04d2" hex"073b" hex"09a3" hex"0c0b" hex"0e71"
        hex"10d6" hex"133b" hex"159d" hex"17fe" hex"1a5d" hex"1cba" hex"1f15" hex"216d" hex"23c3" hex"2617" hex"2867"
        hex"2ab4" hex"2cfe" hex"2f45" hex"3189" hex"33c9" hex"3605" hex"383d" hex"3a71" hex"3ca1" hex"3ecc" hex"40f4"
        hex"4316" hex"4535" hex"474e" hex"4963" hex"4b72" hex"4d7d" hex"4f83" hex"5183" hex"537e" hex"5574" hex"5764"
        hex"594f" hex"5b35" hex"5d15" hex"5eef" hex"60c4" hex"6293" hex"645c" hex"661f" hex"67dd" hex"6995" hex"6b47"
        hex"6cf3" hex"6e99" hex"703a" hex"71d4" hex"7369" hex"74f8" hex"7681" hex"7804" hex"7981" hex"7af9" hex"7c6a"
        hex"7dd6" hex"7f3d" hex"809d" hex"81f8" hex"834d" hex"849d" hex"85e7" hex"872b" hex"886a" hex"89a3" hex"8ad7"
        hex"8c06" hex"8d2f" hex"8e54" hex"8f72" hex"908c" hex"91a1" hex"92b0" hex"93bb" hex"94c1" hex"95c2" hex"96be"
        hex"97b5" hex"98a7" hex"9995" hex"9a7f" hex"9b63" hex"9c44" hex"9d20" hex"9df7" hex"9ecb" hex"9f9a" hex"a065"
        hex"a12c" hex"a1ef" hex"a2ae" hex"a369" hex"a420" hex"a4d4" hex"a584" hex"a630" hex"a6d8" hex"a77e" hex"a81f"
        hex"a8bd" hex"a958" hex"a9f0" hex"aa84" hex"ab16" hex"aba4" hex"ac2f" hex"acb7" hex"ad3c" hex"adbe" hex"ae3e"
        hex"aeba" hex"af34" hex"afab" hex"b020" hex"b092" hex"b102" hex"b16f" hex"b1d9" hex"b242" hex"b2a8" hex"b30b"
        hex"b36d" hex"b3cc" hex"b429" hex"b484" hex"b4dd" hex"b534" hex"b589" hex"b5dc" hex"b62d" hex"b67d" hex"b6ca"
        hex"b716" hex"b760" hex"b7a8" hex"b7ef" hex"b834" hex"b877" hex"b8b9" hex"b8fa" hex"b938" hex"b976" hex"b9b2"
        hex"b9ec" hex"ba26" hex"ba5e" hex"ba94" hex"baca" hex"bafe" hex"bb31" hex"bb62" hex"bb93" hex"bbc2" hex"bbf0"
        hex"bc1e" hex"bc4a" hex"bc75" hex"bc9f" hex"bcc8" hex"bcf0" hex"bd17" hex"bd3e" hex"bd63" hex"bd87" hex"bdab"
        hex"bdce" hex"bdf0" hex"be11" hex"be31" hex"be51" hex"be6f" hex"be8d" hex"beab" hex"bec8" hex"bee4" hex"beff"
        hex"bf19" hex"bf34" hex"bf4d" hex"bf66" hex"bf7e" hex"bf96" hex"bfad" hex"bfc3" hex"bfd9" hex"bfef" hex"c003"
        hex"c018" hex"c02c" hex"c03f" hex"c052" hex"c065" hex"c077" hex"c089" hex"c09a" hex"c0ab" hex"c0bb" hex"c0cb"
        hex"c0db" hex"c0ea" hex"c0f9" hex"c107" hex"c116" hex"c123" hex"c131" hex"c13e" hex"c14b" hex"c157" hex"c164"
        hex"c170" hex"c17b" hex"c187" hex"c192" hex"c19d" hex"c1a7" hex"c1b2" hex"c1bc" hex"c1c5" hex"c1cf" hex"c1d8"
        hex"c1e1" hex"c1ea" hex"c1f3" hex"c1fc" hex"c204" hex"c20c" hex"c214" hex"c21b" hex"c223" hex"c22a" hex"c231"
        hex"c238" hex"c23f" hex"c246" hex"c24c" hex"c253" hex"c254" hex"c255" hex"c256" hex"c257" hex"c258" hex"c259"
        hex"c25a" hex"c25b" hex"c25c" hex"c25d" hex"c25e" hex"c25f" hex"c260" hex"c261" hex"c262" hex"c263" hex"c264"
        hex"c265" hex"c266" hex"c267" hex"c268" hex"c269" hex"c26a" hex"c26b" hex"c26c" hex"c26d" hex"c26e" hex"c26f"
        hex"c270" hex"c271" hex"c272" hex"c273" hex"c274" hex"c275" hex"c276" hex"c277" hex"c278" hex"c279" hex"c27a"
        hex"c27b" hex"c27c" hex"c27d" hex"c27e" hex"c27f" hex"c280" hex"c281" hex"c282" hex"c283" hex"c284" hex"c285"
        hex"c286" hex"c287" hex"c288" hex"c289" hex"c28a" hex"c28b" hex"c28c" hex"c28d" hex"c28e" hex"c28f" hex"c290"
        hex"c291" hex"c292" hex"c293" hex"c294" hex"c295" hex"c296" hex"c297" hex"c298" hex"c299" hex"c29a" hex"c29b"
        hex"c29c" hex"c29d" hex"c29e" hex"c29f" hex"c2a0" hex"c2a1" hex"c2a2" hex"c2a3" hex"c2a4" hex"c2a5" hex"c2a6"
        hex"c2a7" hex"c2a8" hex"c2a9" hex"c2aa" hex"c2ab" hex"c2ac" hex"c2ad" hex"c2ae" hex"c2af" hex"c2b0" hex"c2b1"
        hex"c2b2" hex"c2b3" hex"c2b4" hex"c2b5" hex"c2b6" hex"c2b7" hex"c2b8" hex"c2b9" hex"c2ba" hex"c2bb" hex"c2bc"
        hex"c2bd" hex"c2be" hex"c2bf" hex"c2c0" hex"c2c1" hex"c2c2" hex"c2c3" hex"c2c4" hex"c2c5" hex"c2c6" hex"c2c7"
        hex"c2c8" hex"c2c9" hex"c2ca" hex"c2cb" hex"c2cc" hex"c2cd" hex"c2ce" hex"c2cf" hex"c2d0" hex"c2d1" hex"c2d2"
        hex"c2d3" hex"c2d4" hex"c2d5" hex"c2d6" hex"c2d7" hex"c2d8" hex"c2d9" hex"c2da" hex"c2db" hex"c2dc" hex"c2dd"
        hex"c2de" hex"c2df" hex"c2e0" hex"c2e1" hex"c2e2" hex"c2e3" hex"c2e4" hex"c2e5" hex"c2e6" hex"c2e7" hex"c2e8"
        hex"c2e9" hex"c2ea" hex"c2eb" hex"c2ec" hex"c2ed" hex"c2ee" hex"c2ef" hex"c2f0" hex"c2f1" hex"c2f2" hex"c2f3"
        hex"c2f4" hex"c2f5" hex"c2f6" hex"c2f7" hex"c2f8" hex"c2f9" hex"c2fa" hex"c2fb" hex"c2fc" hex"c2fd" hex"c2fe"
        hex"c2ff" hex"c300" hex"c301" hex"c302" hex"c303" hex"c304" hex"c305" hex"c306" hex"c307" hex"c308" hex"c309"
        hex"c30a" hex"c30b" hex"c30c" hex"c30d" hex"c30e" hex"c30f" hex"c310" hex"c311" hex"c312" hex"c313" hex"c314"
        hex"c315" hex"c316" hex"c317" hex"c318" hex"c319" hex"c31a" hex"c31b" hex"c31c" hex"c31d" hex"c31e" hex"c31f"
        hex"c320" hex"c321" hex"c322" hex"c323" hex"c324" hex"c325" hex"c326" hex"c327" hex"c328" hex"c329" hex"c32a"
        hex"c32b" hex"c32c" hex"c32d" hex"c32e" hex"c32f" hex"c330" hex"c331" hex"c332" hex"c333" hex"c334" hex"c335"
        hex"c336" hex"c337" hex"c338" hex"c339" hex"c33a" hex"c33b" hex"c33c" hex"c33d" hex"c33e" hex"c33f" hex"c340"
        hex"c341" hex"c342" hex"c343" hex"c344" hex"c345" hex"c346" hex"c347" hex"c348" hex"c349" hex"c34a" hex"c34b"
        hex"c34c" hex"c34d" hex"c34e" hex"c34f" hex"c350";

    /// @dev Does not check price bounds
    function tickToPrice(uint256 tick) internal pure returns (uint256) {
        unchecked {
            bytes memory deltas = PACKED_DELTAS;
            if (tick > MAX_TICK / 2) {
                return WAD / 2 + getDelta(deltas, tick - MAX_TICK / 2);
            } else {
                return WAD - (WAD / 2 + getDelta(deltas, MAX_TICK / 2 - tick));
            }
        }
    }

    /// @dev Returns a tick that maps to the closest tick-aligned price.
    /// @dev If there are two equally close prices, the higher one is preferred.
    function priceToTick(uint256 price) internal pure returns (uint256) {
        unchecked {
            uint256 delta;
            if (price < WAD / 2) {
                delta = WAD - price - WAD / 2;
            } else {
                delta = price - WAD / 2;
            }

            bytes memory deltas = PACKED_DELTAS;
            uint256 lowIndex = 0;

            uint256 highIndex = MAX_TICK;
            while (highIndex - lowIndex > 1) {
                uint256 mid = (lowIndex + highIndex) / 2;
                if (getDelta(deltas, mid) < delta) lowIndex = mid;
                else highIndex = mid;
            }

            uint256 lowDelta = getDelta(deltas, lowIndex);
            uint256 highDelta = getDelta(deltas, highIndex);

            if (price < WAD / 2) {
                if (delta - lowDelta > highDelta - delta) {
                    return MAX_TICK / 2 - highIndex;
                } else {
                    return MAX_TICK / 2 - lowIndex;
                }
            } else {
                if (delta - lowDelta >= highDelta - delta) {
                    return MAX_TICK / 2 + highIndex;
                } else {
                    return MAX_TICK / 2 + lowIndex;
                }
            }
        }
    }

    function getDelta(bytes memory deltas, uint256 index) private pure returns (uint256 wadDelta) {
        assembly ("memory-safe") {
            wadDelta := mul(shr(240, mload(add(add(deltas, 32), mul(2, index)))), PRICE_STEP)
        }
    }
}
