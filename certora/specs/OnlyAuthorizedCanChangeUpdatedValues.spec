// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Position/marketState getters used to express protocol invariants as preconditions.
    function creditOf(bytes32, address) external returns (uint128) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastLossFactor(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
    function lossFactor(bytes32) external returns (uint128) envfree;

    // Summarize toId to be able to reference the id in the rules.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Sound because the protocol doesn't use toMarket.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Over-approximate view functions for prover performance.
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    // Use ghost function summaries (deterministic: same inputs → same output) so that calling
    // updatePositionView twice on unchanged storage returns the same credit value.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 z) internal returns (uint256) => ghostMulDivDown(x, y, z);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 z) internal returns (uint256) => ghostMulDivUp(x, y, z);

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own body on the state, not the effect of the full transaction including callbacks.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.isRatified(Midnight.Offer offer, bytes) external => CVL_isRatified(offer) expect(bytes32);
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    // Proven in the rule mulDivZero in MulDiv.spec
    axiom forall uint256 y. forall uint256 z. ghostMulDivDown(0, y, z) == 0;

    // Proven in the rule mulDivZero in MulDiv.spec
    axiom forall uint256 x. forall uint256 z. ghostMulDivDown(x, 0, z) == 0;

    // Proven in the rule mulDivIdentity in MulDiv.spec
    axiom forall uint256 x. forall uint256 y. y > 0 => ghostMulDivDown(x, y, y) == x;

    // Proven in the rule mulDivArgumentLesserThanDenominator in MulDiv.spec
    axiom forall uint256 x. forall uint256 y. forall uint256 z. y <= z => ghostMulDivDown(x, y, z) <= x;
}

ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    // Proven in the rule mulDivZero in MulDiv.spec
    axiom forall uint256 y. forall uint256 z. ghostMulDivUp(0, y, z) == 0;

    // Proven in the rule mulDivZero in MulDiv.spec
    axiom forall uint256 x. forall uint256 z. ghostMulDivUp(x, 0, z) == 0;

    // Proven in the rule mulDivIdentity in MulDiv.spec
    axiom forall uint256 x. forall uint256 y. y > 0 => ghostMulDivUp(x, y, y) == x;

    // Proven in the rule mulDivArgumentLesserThanDenominator in MulDiv.spec
    axiom forall uint256 x. forall uint256 y. forall uint256 z. y <= z => ghostMulDivUp(x, y, z) <= x;

    // Proven in the rule mulDivResidualBound in MulDiv.spec
    axiom forall uint256 x. forall uint256 y. forall uint256 d. (x <= d && y <= d) => x - ghostMulDivUp(x, y, d) <= d - y;
}

/// HELPERS ///

ghost mapping(address => bool) makerRatified {
    init_state axiom forall address a. makerRatified[a] == false;
}

function CVL_isRatified(Midnight.Offer offer) returns bytes32 {
    bytes32 result;
    makerRatified[offer.maker] = true;
    return result;
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

/// UPDATED VALUES CHANGE RULES ///

/// An unauthorized caller cannot change a user's updated credit or updated pending fee except via liquidate.
/// accruedFee is intentionally excluded: updatePosition is permissionless and can set the fees to 0.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeUpdatedValuesExceptLiquidate(env e, method f, calldataarg args, Midnight.Market market, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    require e.block.timestamp <= max_uint128, "realistic timestamp, needed for the uint128 cast";

    bytes32 id = summaryToId(market);
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    require pendingFee(id, user) <= creditOf(id, user), "see pendingContinuousFeeBoundedByCredit";
    require lastLossFactor(id, user) <= lossFactor(id), "see lastLossFactorLeqMarketLossFactor";
    require lastAccrual(id, user) <= require_uint128(e.block.timestamp), "lastAccrual <= block.timestamp by timestamp monotonicity";

    uint128 updatedCreditBefore;
    uint128 updatedPendingFeeBefore;
    updatedCreditBefore, updatedPendingFeeBefore, _ = updatePositionView(e, market, id, user);
    f(e, args);
    uint128 updatedCreditAfter;
    uint128 updatedPendingFeeAfter;
    updatedCreditAfter, updatedPendingFeeAfter, _ = updatePositionView(e, market, id, user);

    assert (updatedCreditAfter == updatedCreditBefore && updatedPendingFeeAfter == updatedPendingFeeBefore) || userIsAuthorized || makerRatified[user];
}
