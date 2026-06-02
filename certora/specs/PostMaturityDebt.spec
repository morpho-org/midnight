// SPDX-License-Identifier: GPL-2.0-or-later

// This spec verifies the post-maturity debt property discussed by the protocol team:
// "Post maturity, the liquidation is locked or the debt cannot increase."
//
// The property is "strong": it must hold at every external-call boundary (i.e. at every
// callback), not only at the end of a transaction. The concern raised in the discussion is
// that the post-maturity debt-increase check in `take` (Midnight.sol:391,
// `CannotIncreaseDebtPostMaturity`) is evaluated relative to the callbacks, so we want to
// rule out a trace where, at callback time, a borrower has both an increased debt and an
// unlocked liquidation (which would enable an atomic increase-debt-then-liquidate-self).
//
// We model every callback as a CHECKPOINT summary: instead of executing arbitrary callback
// code, the summary records whether the property holds at that boundary. Reentrant calls back
// into Midnight are not executed; their own effect is covered compositionally by running this
// same parametric rule on each entry point. This matches the no-reentrancy modeling convention
// already used in BalanceEffects.spec, while additionally asserting the property at boundaries.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // toId is summarized by the real (deterministic, injective) keccak hash of the market.
    // We use the summary to record each market's maturity, keyed by its id, into a ghost.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Internals irrelevant to debt tracking are over-approximated to simplify the task.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Callbacks: each one is a checkpoint that records the property at the external-call boundary
    // and returns CALLBACK_SUCCESS so execution continues to the next boundary and to the end of f.
    function _.isRatified(Midnight.Offer, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => callbackCheckpoint() expect(bytes32);
    function _.onFlashLoan(address, address[], uint256[], bytes) external => callbackCheckpoint() expect(bytes32);
}

/// GHOSTS ///

// Maturity of the market whose id (keccak hash) is the key. Set in summaryToId on every touchMarket.
persistent ghost mapping(bytes32 => mathint) idMaturity;

// The (id, user) position the property is checked against. Left unconstrained => universally quantified.
persistent ghost bytes32 trackedId;

persistent ghost address trackedUser;

// Snapshot of the tracked position's debt at the entry of the verified function.
persistent ghost mathint trackedDebtBefore;

// block.timestamp of the verified call (constant within a transaction).
persistent ghost mathint blockTimestamp;

// True iff the property held at every external-call boundary reached so far.
persistent ghost bool propHeldAtBoundaries;

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    bytes32 id = Utils.hashMarket(market);
    idMaturity[id] = to_mathint(market.maturity);
    return id;
}

// mulDiv summary copied from Midnight.spec: enough algebraic facts without bit-precise reasoning.
function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 r;
    require x == 0 => r == 0;
    require d > 0 && y <= d => r <= x;
    require d > 0 && x <= d && y <= d => x - r <= d - y;
    return r;
}

// The property under verification, evaluated on the current state.
// Post maturity => liquidation is locked OR the tracked debt did not increase since entry.
function strongPropertyHolds() returns bool {
    return blockTimestamp > idMaturity[trackedId] => (liquidationLocked(trackedId, trackedUser) || debtOf(trackedId, trackedUser) <= trackedDebtBefore);
}

function callbackCheckpoint() returns bytes32 {
    propHeldAtBoundaries = propHeldAtBoundaries && strongPropertyHolds();
    return Utils.callbackSuccess();
}

/// RULES ///

// For any function and any post-maturity position, the liquidation is locked or the debt does not increase
rule lockedOrDebtCannotIncreasePostMaturity(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    blockTimestamp = to_mathint(e.block.timestamp);
    trackedDebtBefore = to_mathint(debtOf(trackedId, trackedUser));
    propHeldAtBoundaries = true;

    f(e, args);

    assert propHeldAtBoundaries, "strong property held at every callback boundary";
    assert strongPropertyHolds(), "strong property holds at the end of the call";
}

// Post maturity, the debt cannot increase at all, dropping the "liquidation locked" disjunct. 
// Because the post-maturity check in take precedes the debt write and the callbacks, no path increases debt past maturity, 
// so this stronger statement is expected to hold both at callback boundaries and at the end.
rule debtCannotIncreasePostMaturity(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    // idMaturity[trackedId] is populated during f (in summaryToId), so the post-maturity condition
    // is evaluated in the post-state. If f never touches trackedId, its debt is unchanged and the
    // implication holds regardless of the (then irrelevant) recorded maturity.
    blockTimestamp = to_mathint(e.block.timestamp);
    mathint debtBefore = to_mathint(debtOf(trackedId, trackedUser));

    f(e, args);

    assert blockTimestamp > idMaturity[trackedId] => debtOf(trackedId, trackedUser) <= debtBefore;
}
