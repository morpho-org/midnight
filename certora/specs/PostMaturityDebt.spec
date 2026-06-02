// SPDX-License-Identifier: GPL-2.0-or-later

// Property: "Post maturity, the liquidation is locked or the debt cannot increase."
//
// For an arbitrary position (id, user), post maturity (block.timestamp > maturity) the position is
// either liquidation-locked or its debt did not increase relative to the start of the call. The only
// moment `liquidationLocked` can be true is during the callbacks of `take` (it is set on transient
// storage right before the callbacks and cleared right after), so the property is checked at every
// external-call boundary, and at the end of the call.
//
// Modeling choices, kept minimal:
// - `toId` is summarized to keccak(market) and, in the same call, the market's maturity is recorded
//   under that id. This is the one structural summary, and it is needed for soundness: the real `toId`
//   returns a 160-bit CREATE2 address, so two different markets (with different maturities) could share
//   an id; recording the maturity under the id that the function actually operates on ties the maturity
//   in the property to the maturity used by take's guard (Midnight.sol, CannotIncreaseDebtPostMaturity).
// - All other summaries are plain NONDET, i.e. sound over-approximations: they only add behaviors and
//   assume nothing. They stand for internals irrelevant to the seller's debt and to the lock (the
//   post-maturity debt-increase guard in `take` is `units - min(units, credit)`).
// - The single genuine assumption is that callbacks do not re-enter Midnight (they are summarized to a
//   checkpoint that records the property at the boundary and returns CALLBACK_SUCCESS). This is inherent
//   to stating a callback-time property; reentrant entries are themselves instances of this same rule.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Records each market's maturity under its id (keccak). Restores id injectivity (vs 160-bit address).
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => recordMaturity(market);
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Callbacks: assumed not to re-enter. Each records the property at the external-call boundary and
    // returns CALLBACK_SUCCESS so execution continues to the next boundary and to the end of the call.
    function _.isRatified(Midnight.Offer, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => callbackCheckpoint() expect(bytes32);
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => callbackCheckpoint() expect(bytes32);
    function _.onFlashLoan(address, address[], uint256[], bytes) external => callbackCheckpoint() expect(bytes32);
}

/// GHOSTS ///

// Maturity of the market whose id (keccak) is the key. Set in recordMaturity on every toId.
persistent ghost mapping(bytes32 => mathint) idMaturity;

// The (id, user) position the property is checked against. Left unconstrained => universally quantified.
persistent ghost bytes32 trackedId;

persistent ghost address trackedUser;

// Snapshot of the tracked debt at the start of the call, and the call's block.timestamp.
persistent ghost mathint trackedDebtBefore;

persistent ghost mathint blockTimestamp;

// True if the property held at every external-call boundary reached so far.
persistent ghost bool propHeldAtBoundaries;

/// HELPERS ///

function recordMaturity(Midnight.Market market) returns bytes32 {
    bytes32 id = Utils.hashMarket(market);
    idMaturity[id] = to_mathint(market.maturity);
    return id;
}

function callbackCheckpoint() returns bytes32 {
    propHeldAtBoundaries = propHeldAtBoundaries && (blockTimestamp > idMaturity[trackedId] => (liquidationLocked(trackedId, trackedUser) || debtOf(trackedId, trackedUser) <= trackedDebtBefore));
    return Utils.callbackSuccess();
}

/// RULE ///

rule lockedOrDebtCannotIncreasePostMaturity(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    blockTimestamp = to_mathint(e.block.timestamp);
    trackedDebtBefore = to_mathint(debtOf(trackedId, trackedUser));
    propHeldAtBoundaries = true;

    f(e, args);

    assert propHeldAtBoundaries;
    assert blockTimestamp > idMaturity[trackedId] => (liquidationLocked(trackedId, trackedUser) || debtOf(trackedId, trackedUser) <= trackedDebtBefore);
}
