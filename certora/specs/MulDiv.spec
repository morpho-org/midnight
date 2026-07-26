// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
}

function mathMulDivDown(mathint a, mathint b, mathint d) returns mathint {
    if (d == 0) {
        return 0;
    } else {
        return a * b / d;
    }
}

function mathMulDivUp(mathint a, mathint b, mathint d) returns mathint {
    if (d == 0) {
        return 0;
    } else {
        return (a * b + d - 1) / d;
    }
}

/// RULES ///

/* these proves the axiom used in the other specs */

rule mulDivZero(uint256 a, uint256 b, uint256 d) {
    assert mulDivDown(0, b, d) == 0;
    assert mulDivUp(0, b, d) == 0;
    assert mulDivDown(a, 0, d) == 0;
    assert mulDivUp(a, 0, d) == 0;
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

// 1-Lipschitz in the first argument when b <= d: the result cannot grow faster than the numerator a.
rule mulDivLipschitzA(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    assert b <= d && a1 <= a2 => mulDivDown(a2, b, d) - mulDivDown(a1, b, d) <= a2 - a1;
    assert b <= d && a1 <= a2 => mulDivUp(a2, b, d) - mulDivUp(a1, b, d) <= a2 - a1;
}

// 1-Lipschitz in the second argument when a <= d: the result cannot grow faster than the numerator b.
rule mulDivLipschitzB(uint256 a, uint256 b1, uint256 b2, uint256 d) {
    assert a <= d && b1 <= b2 => mulDivDown(a, b2, d) - mulDivDown(a, b1, d) <= b2 - b1;
    assert a <= d && b1 <= b2 => mulDivUp(a, b2, d) - mulDivUp(a, b1, d) <= b2 - b1;
}

rule mulDivAddDownDown(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1, b, d) + mulDivDown(a2, b, d) <= mulDivDown(a1plusa2, b, d);
}

// Sub-additivity upper bound for mulDivDown: floor((a1+a2)*b/d) <= floor(a1*b/d) + floor(a2*b/d) + 1.
rule mulDivAddDownDownTight(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1plusa2, b, d) <= mulDivDown(a1, b, d) + mulDivDown(a2, b, d) + 1;
}

// Super-additivity upper bound for mulDivUp: ceil((a1+a2)*b/d) <= ceil(a1*b/d) + ceil(a2*b/d).
rule mulDivAddUpUp(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivUp(a1plusa2, b, d) <= mulDivUp(a1, b, d) + mulDivUp(a2, b, d);
}

// Super-additivity lower bound for mulDivUp: ceil(a1*b/d) + ceil(a2*b/d) <= ceil((a1+a2)*b/d) + 1.
rule mulDivAddUpUpTight(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivUp(a1, b, d) + mulDivUp(a2, b, d) <= mulDivUp(a1plusa2, b, d) + 1;
}

// Getter-form double-mulDivUp sub-additivity, with zero slack: for
//   g(x) = mulDivUp(mulDivUp(x, p, S), W, L)   (the per-collateral getter term, with L >= W),
// and s <= a,  g(a) <= g(a - s) + g(s).
// Both ceil layers are sub-additive with zero slack (single-layer is mulDivAddUpUp above), and the
// composition carries the same zero slack: the inner ceil gives mulDivUp(a,p,S) <= mulDivUp(a-s,p,S) +
// mulDivUp(s,p,S) (a = (a-s) + s), then monotonicity + sub-additivity of the outer ceil close it. Used
// by RealizableBadDebtLiquidate.spec to bound the getter-sum drop g(c_k) - g(c_k - seized) by g(seized)
// on the single seized collateral, which is exactly the slack the loose single-layer axioms left open.
rule mulDivUpDoubleSubAdditive(uint256 a, uint256 s, uint256 p, uint256 S, uint256 W, uint256 L) {
    require s <= a;
    require S > 0 && W > 0 && L >= W;

    uint256 innerA = mulDivUp(a, p, S);
    uint256 innerAS = mulDivUp(require_uint256(a - s), p, S);
    uint256 innerS = mulDivUp(s, p, S);

    uint256 ga = mulDivUp(innerA, W, L);
    uint256 gas = mulDivUp(innerAS, W, L);
    uint256 gs = mulDivUp(innerS, W, L);

    assert to_mathint(ga) <= to_mathint(gas) + to_mathint(gs);
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

// Getter-form seize valuation bound: valuing (up-up) the collateral that liquidate seizes (down-down)
// for repaidUnits r never exceeds r, when the seize and the valuation share the same factor l.
rule mulDivSeizeValueBounded(uint256 r, uint256 l, uint256 price, uint256 wad, uint256 scale) {
    require l > 0 && price > 0 && wad > 0 && scale > 0;
    uint256 seized = mulDivDown(mulDivDown(r, l, wad), scale, price);
    assert mulDivUp(mulDivUp(seized, price, scale), wad, l) <= r;
}

rule mulDivArgumentLesserThanDenominator(uint256 a, uint256 b, uint256 d) {
    assert a <= d => mulDivDown(a, b, d) <= b;
    assert a <= d => mulDivUp(a, b, d) <= b;
    assert b <= d => mulDivDown(a, b, d) <= a;
    assert b <= d => mulDivUp(a, b, d) <= a;
}

// Identity (b = d = x): floor(a*x/x) = ceil(a*x/x) = a.
rule mulDivIdentity(uint256 a, uint256 x) {
    assert x != 0 => mulDivDown(a, x, x) == a;
    assert x != 0 => mulDivUp(a, x, x) == a;
}

rule mulDivDownRoundsDown(uint256 a, uint256 b, uint256 d) {
    assert mulDivDown(a, b, d) * d <= a * b;
}

rule mulDivDownTightBound(uint256 a, uint256 b, uint256 d) {
    assert (mulDivDown(a, b, d) + 1) * d > a * b;
}

rule mulDivUpRoundsUp(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(a, b, d) * d >= a * b;
}

rule mulDivUpGeqMulDivDown(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(a, b, d) >= mulDivDown(a, b, d);
}

rule mulDivUpTightBound(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(a, b, d) > 0 => (mulDivUp(a, b, d) - 1) * d < a * b;
}

rule mulDivUpUpperBound(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(a, b, d) * d <= a * b + d - 1;
}

rule mulDivResidualBound(uint256 a, uint256 b, uint256 d) {
    assert a <= d && b <= d => a - mulDivDown(a, b, d) <= d - b;
    assert a <= d && b <= d => a - mulDivUp(a, b, d) <= d - b;
}

rule mathMulDivZero(mathint a, mathint b, mathint d) {
    assert d > 0 => mathMulDivDown(0, b, d) == 0;
    assert d > 0 => mathMulDivUp(0, b, d) == 0;
    assert d > 0 => mathMulDivDown(a, 0, d) == 0;
    assert d > 0 => mathMulDivUp(a, 0, d) == 0;
}

rule mathMulDivMonotoneA(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && b >= 0 && d >= 0 && a1 <= a2 => mathMulDivDown(a1, b, d) <= mathMulDivDown(a2, b, d);
    assert a1 >= 0 && b >= 0 && d >= 0 && a1 <= a2 => mathMulDivUp(a1, b, d) <= mathMulDivUp(a2, b, d);
}

rule mathMulDivMonotoneB(mathint a, mathint b1, mathint b2, mathint d) {
    assert a >= 0 && b1 >= 0 && d >= 0 && b1 <= b2 => mathMulDivDown(a, b1, d) <= mathMulDivDown(a, b2, d);
    assert a >= 0 && b1 >= 0 && d >= 0 && b1 <= b2 => mathMulDivUp(a, b1, d) <= mathMulDivUp(a, b2, d);
}

rule mathMulDivMonotoneD(mathint a, mathint b, mathint d1, mathint d2) {
    assert a >= 0 && b >= 0 && 0 < d1 && d1 <= d2 => mathMulDivDown(a, b, d1) >= mathMulDivDown(a, b, d2);
    assert a >= 0 && b >= 0 && 0 < d1 && d1 <= d2 => mathMulDivUp(a, b, d1) >= mathMulDivUp(a, b, d2);
}

// 1-Lipschitz in the first argument when b <= d: the result cannot grow faster than the numerator a.
rule mathMulDivLipschitzA(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && b >= 0 && b <= d && a1 <= a2 => mathMulDivDown(a2, b, d) - mathMulDivDown(a1, b, d) <= a2 - a1;
    assert a1 >= 0 && b >= 0 && b <= d && a1 <= a2 => mathMulDivUp(a2, b, d) - mathMulDivUp(a1, b, d) <= a2 - a1;
}

// 1-Lipschitz in the second argument when a <= d: the result cannot grow faster than the numerator b.
rule mathMulDivLipschitzB(mathint a, mathint b1, mathint b2, mathint d) {
    assert a >= 0 && b1 >= 0 && a <= d && b1 <= b2 => mathMulDivDown(a, b2, d) - mathMulDivDown(a, b1, d) <= b2 - b1;
    assert a >= 0 && b1 >= 0 && a <= d && b1 <= b2 => mathMulDivUp(a, b2, d) - mathMulDivUp(a, b1, d) <= b2 - b1;
}

rule mathMulDivAddDownDown(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => mathMulDivDown(a1, b, d) + mathMulDivDown(a2, b, d) <= mathMulDivDown(a1 + a2, b, d);
}

// Sub-additivity upper bound for mathMulDivDown: floor((a1+a2)*b/d) <= floor(a1*b/d) + floor(a2*b/d) + 1.
rule mathMulDivAddDownDownTight(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && a2 >= 0 => mathMulDivDown(a1 + a2, b, d) <= mathMulDivDown(a1, b, d) + mathMulDivDown(a2, b, d) + 1;
}

// Super-additivity upper bound for mathMulDivUp: ceil((a1+a2)*b/d) <= ceil(a1*b/d) + ceil(a2*b/d).
rule mathMulDivAddUpUp(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && a2 >= 0 => mathMulDivUp(a1 + a2, b, d) <= mathMulDivUp(a1, b, d) + mathMulDivUp(a2, b, d);
}

// Super-additivity lower bound for mathMulDivUp: ceil(a1*b/d) + ceil(a2*b/d) <= ceil((a1+a2)*b/d) + 1.
rule mathMulDivAddUpUpTight(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => mathMulDivUp(a1, b, d) + mathMulDivUp(a2, b, d) <= mathMulDivUp(a1 + a2, b, d) + 1;
}

rule mathMulDivAddDownUp(mathint a1, mathint a2, mathint b, mathint d) {
    assert a1 >= 0 && a2 >= 0 => mathMulDivDown(a1, b, d) + mathMulDivUp(a2, b, d) >= mathMulDivDown(a1 + a2, b, d);
}

rule mathMulDivInverseDownUp(mathint a, mathint b, mathint d) {
    assert b > 0 && d > 0 => a <= mathMulDivDown(mathMulDivUp(a, b, d), d, b);
}

rule mathMulDivInverseUpDown(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && d > 0 => mathMulDivUp(mathMulDivDown(a, b, d), d, b) <= a;
}

rule mathMulDivArgumentLesserThanDenominator(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && a <= d => mathMulDivDown(a, b, d) <= b;
    assert a >= 0 && b >= 0 && a <= d => mathMulDivUp(a, b, d) <= b;
    assert a >= 0 && b >= 0 && b <= d => mathMulDivDown(a, b, d) <= a;
    assert a >= 0 && b >= 0 && b <= d => mathMulDivUp(a, b, d) <= a;
}

// Identity (b = d = x): floor(a*x/x) = ceil(a*x/x) = a.
rule mathMulDivIdentity(mathint a, mathint x) {
    assert a >= 0 && x > 0 => mathMulDivDown(a, x, x) == a;
    assert a >= 0 && x > 0 => mathMulDivUp(a, x, x) == a;
}

rule mathMulDivDownRoundsDown(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 => mathMulDivDown(a, b, d) * d <= a * b;
}

rule mathMulDivDownTightBound(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && d > 0 => (mathMulDivDown(a, b, d) + 1) * d > a * b;
}

rule mathMulDivUpRoundsUp(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && d > 0 => mathMulDivUp(a, b, d) * d >= a * b;
}

rule mathMulDivUpGeqMulDivDown(mathint a, mathint b, mathint d) {
    assert mathMulDivUp(a, b, d) >= mathMulDivDown(a, b, d);
}

rule mathMulDivUpTightBound(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && d > 0 && mathMulDivUp(a, b, d) > 0 => (mathMulDivUp(a, b, d) - 1) * d < a * b;
}

rule mathMulDivUpUpperBound(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && d > 0 => mathMulDivUp(a, b, d) * d <= a * b + d - 1;
}

rule mathMulDivResidualBound(mathint a, mathint b, mathint d) {
    assert a >= 0 && b >= 0 && a <= d && b <= d => a - mathMulDivDown(a, b, d) <= d - b;
    assert a >= 0 && b >= 0 && a <= d && b <= d => a - mathMulDivUp(a, b, d) <= d - b;
}

rule mulDivEqMathMulDiv(uint256 a, uint256 b, uint256 d) {
    assert mulDivDown(a, b, d) == mathMulDivDown(a, b, d);
    assert mulDivUp(a, b, d) == mathMulDivUp(a, b, d);
}

rule mulDivDownReverts(uint256 a, uint256 b, uint256 d) {
    mulDivDown@withrevert(a, b, d);

    assert lastReverted == (d == 0 || a * b >= 2 ^ 256);
}

rule mulDivUpReverts(uint256 a, uint256 b, uint256 d) {
    mulDivUp@withrevert(a, b, d);

    assert lastReverted == (d == 0 || a * b + d - 1 >= 2 ^ 256);
}
