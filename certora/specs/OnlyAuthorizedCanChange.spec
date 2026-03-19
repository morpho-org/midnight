// SPDX-License-Identifier: GPL-2.0-or-later

import "Midnight.spec";

methods {
    function feeRecipient() external returns (address) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Assume no reentrancy: callbacks do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

definition noAccrual(env e, bytes32 id, address borrower) returns bool = currentContract.position[id][borrower].pendingFee == 0 || e.block.timestamp == currentContract.position[id][borrower].lastContinuousFeeAccrual;

use invariant noRemainingContinuousFeeWithoutDebt;

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

function CVL_signer() returns address {
    address result;
    signed[result] = true;
    return result;
}

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via liquidate and slash.
/// PASSIVE_FEE_RECIPIENT's credit can increase via fee accrual without authorization.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptLiquidateAndSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool isPassiveFeeRecipient = user == Utils.passiveFeeRecipient();

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || signed[user] || isPassiveFeeRecipient;
}

/// COLLATERAL CHANGE RULES ///

/// An unauthorized caller cannot change a user's collateral except via liquidate.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant collateral changes are not covered.
rule onlyAuthorizedCanChangeCollateralExceptLiquidate(env e, method f, calldataarg args, bytes32 id, address user, uint256 collateralIndex) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 collateralBefore = collateralOf(id, user, collateralIndex);
    f(e, args);
    uint256 collateralAfter = collateralOf(id, user, collateralIndex);

    assert collateralAfter == collateralBefore || userIsAuthorized;
}
