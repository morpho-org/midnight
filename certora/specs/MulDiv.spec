// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
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

    assert ga <= gas + gs;
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
