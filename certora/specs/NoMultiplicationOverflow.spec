// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that no multiplication overflow occurs in mulDivDown or mulDivUp.
//
// mulDivDown(x, y, d) computes (x * y) / d with Solidity 0.8 checked arithmetic.
// mulDivUp(x, y, d) computes (x * y + (d - 1)) / d with Solidity 0.8 checked arithmetic.
// The multiplication x * y must not exceed type(uint256).max, or the transaction reverts.
//
// maxLif(uint256, uint256) is excluded: it is a pure function callable with arbitrary inputs.
// Internal calls use WAD-scale values where its intermediate multiplications
// (WAD * WAD = 1e36 and cursor * (WAD - lltv) <= WAD^2 = 1e36) cannot overflow uint256.
//
// The toId summary follows the approach from CreatedObligations.spec and encodes
// obligation field bounds (lltv, maxLif, maturity) proven in other specs.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Oracle prices bounded to uint128: collateral * price fits in uint256 ((2^128-1)^2 < 2^256-1).
    function _.price() external => boundedPrice() expect(uint256);

    // Deterministic toId: links calldata obligations to validated state from touchObligation.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Summarize CREATE2 opcode used by IdLib.storeInCode.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;

    // Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
    function Midnight.maxLif(uint256 lltv, uint256 cursor) internal returns (uint256) => maxLifSummary(lltv);

    // Hook mulDivDown and mulDivUp to track overflow.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// GHOSTS ///

persistent ghost bool mulOverflow;

/// HOOKS ///

// lossIndex > 0: the protocol stops behaving correctly if this reaches 0 (documented).
hook Sload uint128 value obligationState[KEY bytes32 id].lossIndex {
    require value > 0;
}

// Follows from userLossIndexLeqObligationLossIndex in Midnight.spec and the hook above.
hook Sload uint128 value position[KEY bytes32 id][KEY address user].lossIndex {
    require value > 0;
}

/// SUMMARIES ///

definition WAD() returns uint256 = 1000000000000000000;

// Proven in CreatedObligations.spec (createdObligationsHaveLltvLessThanOrEqualToOne)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity bounded to uint64: max_uint128 * max_uint32 * max_uint64 = 2^224 < 2^256.
function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    require forall uint256 i. i < obligation.collaterals.length => obligation.collaterals[i].lltv <= WAD();
    require forall uint256 i. i < obligation.collaterals.length => obligation.collaterals[i].maxLif >= WAD() && obligation.collaterals[i].maxLif <= 2 * WAD();
    require obligation.maturity <= max_uint64;
    return Utils.hashObligation(obligation);
}

// Oracle prices are positive and bounded to uint128.
function boundedPrice() returns uint256 {
    uint256 price;
    require price > 0;
    require price <= max_uint128;
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price > 0;
    require price <= WAD();
    return price;
}

// Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
function maxLifSummary(uint256 lltv) returns uint256 {
    uint256 result;
    require result >= WAD();
    require result <= 2 * WAD();
    return result;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product;
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;

    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product + d - 1;
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;

    return result;
}

// Proven in CreatedObligations.spec and ExactMath.spec.
// Maturity bounded to uint64: max_uint128 * max_uint32 * max_uint64 = 2^224 < 2^256.
function requireObligationBounds(Midnight.Obligation obligation) {
    require forall uint256 i. i < obligation.collaterals.length => obligation.collaterals[i].lltv <= WAD();
    require forall uint256 i. i < obligation.collaterals.length => obligation.collaterals[i].maxLif >= WAD() && obligation.collaterals[i].maxLif <= 2 * WAD();
    require obligation.maturity <= max_uint64;
}

/// RULES ///

// Exclude maxLif (see header) and view functions (separate rules below).
// Obligation field bounds for non-view functions come from summaryToId.
rule noMultiplicationOverflow(method f, env e, calldataarg args) filtered { f -> f.selector != sig:maxLif(uint256, uint256).selector && f.selector != sig:isHealthy(Midnight.Obligation, bytes32, address).selector && f.selector != sig:updatePositionView(Midnight.Obligation, bytes32, address).selector } {
    require !mulOverflow;
    f(e, args);
    assert !mulOverflow, "multiplication overflow detected in mulDivDown or mulDivUp";
}

// View functions take id as a separate parameter (not derived from the obligation),
// so summaryToId bounds don't apply. Explicit obligation bounds are needed.
rule noMultiplicationOverflowIsHealthy(env e, Midnight.Obligation obligation, bytes32 id, address borrower) {
    require !mulOverflow;
    requireObligationBounds(obligation);
    isHealthy(e, obligation, id, borrower);
    assert !mulOverflow, "multiplication overflow detected in mulDivDown or mulDivUp";
}

rule noMultiplicationOverflowUpdatePositionView(env e, Midnight.Obligation obligation, bytes32 id, address user) {
    require !mulOverflow;
    requireObligationBounds(obligation);
    updatePositionView(e, obligation, id, user);
    assert !mulOverflow, "multiplication overflow detected in mulDivDown or mulDivUp";
}
