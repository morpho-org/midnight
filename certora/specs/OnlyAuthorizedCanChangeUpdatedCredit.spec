// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

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
    // Axioms proven in MulDiv.spec.
    axiom forall uint256 y. forall uint256 z. ghostMulDivDown(0, y, z) == 0;
    axiom forall uint256 x. forall uint256 z. ghostMulDivDown(x, 0, z) == 0;
    axiom forall uint256 x. forall uint256 y. y > 0 => ghostMulDivDown(x, y, y) == x;
}

ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    // Axioms proven in MulDiv.spec.
    axiom forall uint256 y. forall uint256 z. ghostMulDivUp(0, y, z) == 0;
    axiom forall uint256 x. forall uint256 z. ghostMulDivUp(x, 0, z) == 0;
    axiom forall uint256 x. forall uint256 y. y > 0 => ghostMulDivUp(x, y, y) == x;
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

/// UPDATED CREDIT CHANGE RULES ///

/// An unauthorized caller cannot change a user's updated credit except via liquidate.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeUpdatedCreditExceptLiquidate(env e, method f, calldataarg args, Midnight.Market market, address user) {
    require e.block.timestamp <= max_uint128, "realistic timestamp, needed for the uint128 cast";

    bytes32 id = summaryToId(market);
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint128 updatedCreditBefore;
    updatedCreditBefore, _, _ = updatePositionView(e, market, id, user);
    f(e, args);
    uint128 updatedCreditAfter;
    updatedCreditAfter, _, _ = updatePositionView(e, market, id, user);

    assert (updatedCreditAfter == updatedCreditBefore) || userIsAuthorized || makerRatified[user];
}
