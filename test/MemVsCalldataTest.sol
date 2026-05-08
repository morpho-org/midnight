// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console2} from "../lib/forge-std/src/console2.sol";

struct Big {
    uint256 a;
    uint256 b;
    uint256 c;
    uint256 d;
    uint256 e;
    uint256 f;
    uint256 g;
    uint256 h;
    uint256[] arr;
}

contract MemVsCalldata {
    // 1. Read one field (struct mostly unused).
    function readOneFieldMem(Big memory s) external pure returns (uint256) {
        return s.a;
    }

    function readOneFieldCd(Big calldata s) external pure returns (uint256) {
        return s.a;
    }

    // 2. Read every static field once.
    function readAllOnceMem(Big memory s) external pure returns (uint256) {
        unchecked {
            return s.a + s.b + s.c + s.d + s.e + s.f + s.g + s.h;
        }
    }

    function readAllOnceCd(Big calldata s) external pure returns (uint256) {
        unchecked {
            return s.a + s.b + s.c + s.d + s.e + s.f + s.g + s.h;
        }
    }

    // 3. Read the same field many times in a hot loop.
    function readOneRepeatedMem(Big memory s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            for (uint256 i; i < 100; ++i) {
                sum += s.a;
            }
            return sum;
        }
    }

    function readOneRepeatedCd(Big calldata s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            for (uint256 i; i < 100; ++i) {
                sum += s.a;
            }
            return sum;
        }
    }

    // 4. Iterate the dynamic array once.
    function iterateArrayMem(Big memory s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            uint256 len = s.arr.length;
            for (uint256 i; i < len; ++i) {
                sum += s.arr[i];
            }
            return sum;
        }
    }

    function iterateArrayCd(Big calldata s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            uint256 len = s.arr.length;
            for (uint256 i; i < len; ++i) {
                sum += s.arr[i];
            }
            return sum;
        }
    }

    // 5. Iterate the dynamic array three times.
    function iterateArray3xMem(Big memory s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            uint256 len = s.arr.length;
            for (uint256 k; k < 3; ++k) {
                for (uint256 i; i < len; ++i) {
                    sum += s.arr[i];
                }
            }
            return sum;
        }
    }

    function iterateArray3xCd(Big calldata s) external pure returns (uint256) {
        unchecked {
            uint256 sum;
            uint256 len = s.arr.length;
            for (uint256 k; k < 3; ++k) {
                for (uint256 i; i < len; ++i) {
                    sum += s.arr[i];
                }
            }
            return sum;
        }
    }

    // 6. Hash the whole struct.
    function hashWholeMem(Big memory s) external pure returns (bytes32) {
        return keccak256(abi.encode(s));
    }

    function hashWholeCd(Big calldata s) external pure returns (bytes32) {
        return keccak256(abi.encode(s));
    }

    // 7. Pass the struct down to a helper that needs memory.
    //    The calldata variant must copy at the boundary.
    function toMemHelperMem(Big memory s) external pure returns (uint256) {
        return _memHelper(s);
    }

    function toMemHelperCd(Big calldata s) external pure returns (uint256) {
        return _memHelper(s);
    }

    function _memHelper(Big memory s) internal pure returns (uint256) {
        unchecked {
            return s.a + s.b + s.c + s.d;
        }
    }

    // 8. Pass the struct down to a helper that takes calldata (only available
    //    when the entry param is calldata — for reference / lower bound).
    function toCdHelperCd(Big calldata s) external pure returns (uint256) {
        return _cdHelper(s);
    }

    function _cdHelper(Big calldata s) internal pure returns (uint256) {
        unchecked {
            return s.a + s.b + s.c + s.d;
        }
    }
}

contract MemVsCalldataTest is Test {
    MemVsCalldata internal c;

    Big internal stored;

    function setUp() public {
        c = new MemVsCalldata();
        stored.a = 1;
        stored.b = 2;
        stored.c = 3;
        stored.d = 4;
        stored.e = 5;
        stored.f = 6;
        stored.g = 7;
        stored.h = 8;
        for (uint256 i; i < 32; ++i) {
            stored.arr.push(i + 1);
        }
    }

    function _load() internal view returns (Big memory s) {
        s.a = stored.a;
        s.b = stored.b;
        s.c = stored.c;
        s.d = stored.d;
        s.e = stored.e;
        s.f = stored.f;
        s.g = stored.g;
        s.h = stored.h;
        s.arr = new uint256[](stored.arr.length);
        for (uint256 i; i < stored.arr.length; ++i) {
            s.arr[i] = stored.arr[i];
        }
    }

    function _row(string memory name, uint256 mem, uint256 cd) internal pure {
        // Print memory, calldata, diff (mem - cd). Positive diff means calldata wins.
        console2.log(name);
        console2.log("  memory  ", mem);
        console2.log("  calldata", cd);
        if (mem >= cd) {
            console2.log("  mem-cd  ", mem - cd);
        } else {
            console2.log("  cd-mem  ", cd - mem);
        }
    }

    function test_compareAll() public view {
        Big memory s = _load();
        uint256 g;
        uint256 mem;
        uint256 cd;
        uint256 r;

        // 1. one field
        g = gasleft();
        r = c.readOneFieldMem(s);
        mem = g - gasleft();
        require(r == s.a);
        g = gasleft();
        r = c.readOneFieldCd(s);
        cd = g - gasleft();
        require(r == s.a);
        _row("1) read one field once", mem, cd);

        // 2. read all 8 static fields once
        g = gasleft();
        r = c.readAllOnceMem(s);
        mem = g - gasleft();
        require(r > 0);
        g = gasleft();
        r = c.readAllOnceCd(s);
        cd = g - gasleft();
        require(r > 0);
        _row("2) read all 8 fields once", mem, cd);

        // 3. read one field 100 times
        g = gasleft();
        r = c.readOneRepeatedMem(s);
        mem = g - gasleft();
        require(r > 0);
        g = gasleft();
        r = c.readOneRepeatedCd(s);
        cd = g - gasleft();
        require(r > 0);
        _row("3) read one field 100x", mem, cd);

        // 4. iterate array once (32 elements)
        g = gasleft();
        r = c.iterateArrayMem(s);
        mem = g - gasleft();
        require(r > 0);
        g = gasleft();
        r = c.iterateArrayCd(s);
        cd = g - gasleft();
        require(r > 0);
        _row("4) iterate 32-elem array once", mem, cd);

        // 5. iterate array 3x
        g = gasleft();
        r = c.iterateArray3xMem(s);
        mem = g - gasleft();
        require(r > 0);
        g = gasleft();
        r = c.iterateArray3xCd(s);
        cd = g - gasleft();
        require(r > 0);
        _row("5) iterate 32-elem array 3x", mem, cd);

        // 6. hash the entire struct (abi.encode)
        bytes32 h;
        g = gasleft();
        h = c.hashWholeMem(s);
        mem = g - gasleft();
        require(h != bytes32(0));
        g = gasleft();
        h = c.hashWholeCd(s);
        cd = g - gasleft();
        require(h != bytes32(0));
        _row("6) keccak(abi.encode(s))", mem, cd);

        // 7. forward to a helper that takes memory (calldata path must copy)
        g = gasleft();
        r = c.toMemHelperMem(s);
        mem = g - gasleft();
        require(r > 0);
        g = gasleft();
        r = c.toMemHelperCd(s);
        cd = g - gasleft();
        require(r > 0);
        _row("7) forward to memory helper", mem, cd);

        // 8. calldata->calldata helper (lower bound; no memory peer)
        g = gasleft();
        r = c.toCdHelperCd(s);
        cd = g - gasleft();
        require(r > 0);
        console2.log("8) forward to calldata helper (cd only)");
        console2.log("  calldata", cd);
    }
}
