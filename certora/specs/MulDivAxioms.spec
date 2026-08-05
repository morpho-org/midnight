// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

definition mathMulDivDown(mathint a, mathint b, mathint d) returns mathint = ghostMulDivDown(a, b, d);

definition mathMulDivUp(mathint a, mathint b, mathint d) returns mathint = ghostMulDivUp(a, b, d);

/* these are the axioms proved in MulDiv.spec */

definition axiomMathMulDivDownZeroA(mathint b, mathint d) returns bool = d > 0 => mathMulDivDown(0, b, d) == 0;

definition axiomMathMulDivUpZeroA(mathint b, mathint d) returns bool = d > 0 => mathMulDivUp(0, b, d) == 0;

definition axiomMathMulDivDownZeroB(mathint a, mathint d) returns bool = d > 0 => mathMulDivDown(a, 0, d) == 0;

definition axiomMathMulDivUpZeroB(mathint a, mathint d) returns bool = d > 0 => mathMulDivUp(a, 0, d) == 0;

definition axiomMathMulDivDownMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && b >= 0 && d >= 0 && a1 <= a2 => mathMulDivDown(a1, b, d) <= mathMulDivDown(a2, b, d);

definition axiomMathMulDivUpMonotoneA(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && b >= 0 && d >= 0 && a1 <= a2 => mathMulDivUp(a1, b, d) <= mathMulDivUp(a2, b, d);

definition axiomMathMulDivDownMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = a >= 0 && b1 >= 0 && d >= 0 && b1 <= b2 => mathMulDivDown(a, b1, d) <= mathMulDivDown(a, b2, d);

definition axiomMathMulDivUpMonotoneB(mathint a, mathint b1, mathint b2, mathint d) returns bool = a >= 0 && b1 >= 0 && d >= 0 && b1 <= b2 => mathMulDivUp(a, b1, d) <= mathMulDivUp(a, b2, d);

definition axiomMathMulDivDownMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = a >= 0 && b >= 0 && 0 < d1 && d1 <= d2 => mathMulDivDown(a, b, d1) >= mathMulDivDown(a, b, d2);

definition axiomMathMulDivUpMonotoneD(mathint a, mathint b, mathint d1, mathint d2) returns bool = a >= 0 && b >= 0 && 0 < d1 && d1 <= d2 => mathMulDivUp(a, b, d1) >= mathMulDivUp(a, b, d2);

definition axiomMathMulDivDownMonotoneBD(mathint a, mathint b1, mathint b2, mathint d1, mathint d2) returns bool = a >= 0 && b1 >= 0 && b2 >= 0 && d1 > 0 && d2 > 0 && b1 * d2 <= d1 * b2 => mathMulDivDown(a, b1, d1) <= mathMulDivDown(a, b2, d2);

definition axiomMathMulDivUpMonotoneBD(mathint a, mathint b1, mathint b2, mathint d1, mathint d2) returns bool = a >= 0 && b1 >= 0 && b2 >= 0 && d1 > 0 && d2 > 0 && b1 * d2 <= d1 * b2 => mathMulDivUp(a, b1, d1) <= mathMulDivUp(a, b2, d2);

// 1-Lipschitz in the first argument when b <= d: the result cannot grow faster than the numerator a.
definition axiomMathMulDivDownLipschitzA(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && b >= 0 && b <= d && a1 <= a2 => mathMulDivDown(a2, b, d) - mathMulDivDown(a1, b, d) <= a2 - a1;

definition axiomMathMulDivUpLipschitzA(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && b >= 0 && b <= d && a1 <= a2 => mathMulDivUp(a2, b, d) - mathMulDivUp(a1, b, d) <= a2 - a1;

// 1-Lipschitz in the second argument when a <= d: the result cannot grow faster than the numerator b.
definition axiomMathMulDivDownLipschitzB(mathint a, mathint b1, mathint b2, mathint d) returns bool = a >= 0 && b1 >= 0 && a <= d && b1 <= b2 => mathMulDivDown(a, b2, d) - mathMulDivDown(a, b1, d) <= b2 - b1;

definition axiomMathMulDivUpLipschitzB(mathint a, mathint b1, mathint b2, mathint d) returns bool = a >= 0 && b1 >= 0 && a <= d && b1 <= b2 => mathMulDivUp(a, b2, d) - mathMulDivUp(a, b1, d) <= b2 - b1;

definition axiomMathMulDivAddDownDown(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => mathMulDivDown(a1, b, d) + mathMulDivDown(a2, b, d) <= mathMulDivDown(a1 + a2, b, d);

// Sub-additivity upper bound for mathMulDivDown: floor((a1+a2)*b/d) <= floor(a1*b/d) + floor(a2*b/d) + 1.
definition axiomMathMulDivAddDownDownTight(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 => mathMulDivDown(a1 + a2, b, d) <= mathMulDivDown(a1, b, d) + mathMulDivDown(a2, b, d) + 1;

// Super-additivity upper bound for mathMulDivUp: ceil((a1+a2)*b/d) <= ceil(a1*b/d) + ceil(a2*b/d).
definition axiomMathMulDivAddUpUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 => mathMulDivUp(a1 + a2, b, d) <= mathMulDivUp(a1, b, d) + mathMulDivUp(a2, b, d);

// Super-additivity lower bound for mathMulDivUp: ceil(a1*b/d) + ceil(a2*b/d) <= ceil((a1+a2)*b/d) + 1.
definition axiomMathMulDivAddUpUpTight(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 && b >= 0 && d > 0 => mathMulDivUp(a1, b, d) + mathMulDivUp(a2, b, d) <= mathMulDivUp(a1 + a2, b, d) + 1;

definition axiomMathMulDivAddDownUp(mathint a1, mathint a2, mathint b, mathint d) returns bool = a1 >= 0 && a2 >= 0 => mathMulDivDown(a1, b, d) + mathMulDivUp(a2, b, d) >= mathMulDivDown(a1 + a2, b, d);

definition axiomMathMulDivInverseDownUp(mathint a, mathint b, mathint d) returns bool = b > 0 && d > 0 => a <= mathMulDivDown(mathMulDivUp(a, b, d), d, b);

definition axiomMathMulDivInverseUpDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 => mathMulDivUp(mathMulDivDown(a, b, d), d, b) <= a;

definition axiomMathMulDivDownArgumentLesserThanDenominatorA(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && a <= d => mathMulDivDown(a, b, d) <= b;

definition axiomMathMulDivUpArgumentLesserThanDenominatorA(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && a <= d => mathMulDivUp(a, b, d) <= b;

definition axiomMathMulDivDownArgumentLesserThanDenominatorB(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && b <= d => mathMulDivDown(a, b, d) <= a;

definition axiomMathMulDivUpArgumentLesserThanDenominatorB(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && b <= d => mathMulDivUp(a, b, d) <= a;

// Identity (b = d = x): floor(a*x/x) = ceil(a*x/x) = a.
definition axiomMathMulDivDownIdentity(mathint a, mathint x) returns bool = a >= 0 && x > 0 => mathMulDivDown(a, x, x) == a;

definition axiomMathMulDivUpIdentity(mathint a, mathint x) returns bool = a >= 0 && x > 0 => mathMulDivUp(a, x, x) == a;

definition axiomMathMulDivDownRoundsDown(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 => mathMulDivDown(a, b, d) * d <= a * b;

definition axiomMathMulDivDownTightBound(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 => (mathMulDivDown(a, b, d) + 1) * d > a * b;

definition axiomMathMulDivUpRoundsUp(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 => mathMulDivUp(a, b, d) * d >= a * b;

definition axiomMathMulDivUpGeqMulDivDown(mathint a, mathint b, mathint d) returns bool = mathMulDivUp(a, b, d) >= mathMulDivDown(a, b, d);

definition axiomMathMulDivUpTightBound(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 && mathMulDivUp(a, b, d) > 0 => (mathMulDivUp(a, b, d) - 1) * d < a * b;

definition axiomMathMulDivUpUpperBound(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 => mathMulDivUp(a, b, d) * d <= a * b + d - 1;

definition axiomMathMulDivDownResidualBound(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && a <= d && b <= d => a - mathMulDivDown(a, b, d) <= d - b;

definition axiomMathMulDivUpResidualBound(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && a <= d && b <= d => a - mathMulDivUp(a, b, d) <= d - b;
