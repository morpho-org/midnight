methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
}

/// RULES ///

/* these proves the axiom used in the other specs */

rule mulDivZero(uint256 b, uint256 d) {
    assert mulDivDown(0, b, d) == 0;
    assert mulDivUp(0, b, d) == 0;
}

rule mulDivMonotoneA(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    assert a1 <= a2 => mulDivDown(a1, b, d) <= mulDivDown(a2, b, d);
    assert a1 <= a2 => mulDivUp(a1, b, d) <= mulDivUp(a2, b, d);
}

rule mulDivMonotoneB(uint256 a, uint256 b1, uint256 b2, uint256 d) {
    assert b1 <= b2 => mulDivDown(a, b1, d) <= mulDivDown(a, b2, d);
    assert b1 <= b2 => mulDivUp(a, b1, d) <= mulDivUp(a, b2, d);
}

rule mulDivMonotoneD(uint256 a, uint256 b, uint256 d1, uint256 d2) {
    assert d1 <= d2 => mulDivDown(a, b, d1) >= mulDivDown(a, b, d2);
    assert d1 <= d2 => mulDivUp(a, b, d1) >= mulDivUp(a, b, d2);
}

rule mulDivAddDownDown(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1, b, d) + mulDivDown(a2, b, d) <= mulDivDown(a1plusa2, b, d);
}

rule mulDivAddDownUp(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1, b, d) + mulDivUp(a2, b, d) >= mulDivDown(a1plusa2, b, d);
}

rule mulDivInverseDownUp(uint256 a, uint256 b, uint256 d) {
    assert a <= mulDivDown(mulDivUp(a, b, d), d, b);
}

rule mulDivInverseUpDown(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(mulDivDown(a, b, d), d, b) <= a;
}

rule mulDivLifLLTV(uint256 a, uint256 lif, uint256 lltv, uint256 WAD) {
    assert lltv * lif <= WAD * WAD => mulDivUp(a, lltv, WAD) <= mulDivUp(a, WAD, lif);
}
