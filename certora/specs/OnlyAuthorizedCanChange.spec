// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function feeRecipient() external returns (address) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function session(address user) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // IdLib.toId summary: deterministic for the global obligation, injective otherwise.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation, chainId, midnight);

    // Oracle summary: we assume the price does not change during the execution of a transaction.
    function _.price() external => CVL_price(calledContract) expect(uint256);

    // Summarize complex internal functions irrelevant to authorization checks.
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    // Summarize TickLib functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    // Summarize UtilsLib functions.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128 x) internal returns (uint256) => CVL_msb(x);
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 c) internal returns (uint256) => CVL_mulDivDown(a, b, c);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 c) internal returns (uint256) => CVL_mulDivUp(a, b, c);

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

// Global obligation ghosts: store a single obligation and its id for deterministic/injective toId.

persistent ghost bytes32 globalId;

persistent ghost address globalObligationLoanToken;

persistent ghost uint256 globalObligationCollateralLength;

persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;

persistent ghost mapping(uint256 => address) globalObligationCollateralToken;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralMaxLif;

persistent ghost uint256 globalObligationMaturity;

persistent ghost uint256 globalObligationRcfThreshold;

persistent ghost address globalObligationEnterGate;

persistent ghost address globalObligationLiquidatorGate;

definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool = index < globalObligationCollateralLength => obligation.collaterals[index].oracle == globalObligationCollateralOracle[index] && obligation.collaterals[index].token == globalObligationCollateralToken[index] && obligation.collaterals[index].lltv == globalObligationCollateralLLTV[index] && obligation.collaterals[index].maxLif == globalObligationCollateralMaxLif[index];

function equalsGlobalObligation(Midnight.Obligation obligation) returns bool {
    return obligation.loanToken == globalObligationLoanToken && obligation.collaterals.length == globalObligationCollateralLength && collateralMatches(obligation, 0) && collateralMatches(obligation, 1) && collateralMatches(obligation, 2) && obligation.maturity == globalObligationMaturity && obligation.rcfThreshold == globalObligationRcfThreshold && obligation.enterGate == globalObligationEnterGate && obligation.liquidatorGate == globalObligationLiquidatorGate;
}

function getGlobalObligation() returns Midnight.Obligation {
    Midnight.Obligation obligation;
    require equalsGlobalObligation(obligation), "constrain the obligation to the tracked market parameters";
    return obligation;
}

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    if (equalsGlobalObligation(obligation) && midnight == currentContract) {
        require id == globalId, "obligation matches the tracked market — bind id to globalId'";
    } else {
        require id != globalId, "obligation is a different market — exclude globalId ";
    }
    return id;
}

// Deterministic ghosts for oracle and math functions.

ghost CVL_price(address) returns uint256;

ghost CVL_msb(uint128) returns uint256;

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

definition noAccrual(env e, bytes32 id, address borrower) returns bool = currentContract.position[id][borrower].pendingFee == 0 || e.block.timestamp == currentContract.position[id][borrower].lastAccrual;

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

function CVL_signer() returns address {
    address result;
    signed[result] = true;
    return result;
}

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via updatePosition.
/// PASSIVE_FEE_RECIPIENT's credit can increase via fee accrual without authorization.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptSlashAndLiquidate(env e, method f, calldataarg args, address user) filtered { f -> f.selector != sig:updatePosition(Midnight.Obligation, address).selector } {
    Midnight.Obligation obligation = getGlobalObligation();
    bytes32 id = globalId;

    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool isPassiveFeeRecipient = user == Utils.passiveFeeRecipient();
    bool isHealthyBefore = isHealthy(e, obligation, id, user);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert creditAfter == creditBefore || userIsAuthorized || signed[user] || isPassiveFeeRecipient;
    assert debtAfter == debtBefore || userIsAuthorized || signed[user] || isPassiveFeeRecipient || !isHealthyBefore || obligation.maturity < e.block.timestamp;
}

rule onlyAuthorizedCanChangeCreditAndDebtInLiquidate(env e, address user, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    Midnight.Obligation obligation = getGlobalObligation();
    bytes32 id = globalId;

    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool isPassiveFeeRecipient = user == Utils.passiveFeeRecipient();
    bool isHealthyBefore = isHealthy(e, obligation, id, user);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    uint256 collateralIndex;

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert creditAfter == creditBefore || userIsAuthorized || signed[user] || isPassiveFeeRecipient;
    assert debtAfter == debtBefore || userIsAuthorized || signed[user] || isPassiveFeeRecipient || !isHealthyBefore || obligation.maturity < e.block.timestamp;
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

/// CONSUMED CHANGE RULES ///

/// An unauthorized or unsigned caller cannot change a user's consumed.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant consumed changes are not covered.
rule onlyAuthorizedCanChangeConsumed(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> !f.isView } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 consumedBefore = consumed(user, group);
    f(e, args);
    uint256 consumedAfter = consumed(user, group);

    assert consumedAfter == consumedBefore || userIsAuthorized || signed[user];
}

/// SESSION CHANGE RULES ///

/// An unauthorized caller cannot change a user's session.
rule onlyAuthorizedCanChangeSession(env e, method f, calldataarg args, address user) filtered { f -> !f.isView } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    bytes32 sessionBefore = session(user);
    f(e, args);
    bytes32 sessionAfter = session(user);

    assert sessionAfter == sessionBefore || userIsAuthorized;
}

/// AUTHORIZATION CHANGE RULES ///

/// An unauthorized caller cannot change a user's isAuthorized mapping.
rule onlyAuthorizedCanChangeIsAuthorized(env e, method f, calldataarg args, address authorizer, address authorized) filtered { f -> !f.isView } {
    bool authorizerIsAuthorized = authorizer == e.msg.sender || isAuthorized(authorizer, e.msg.sender);

    bool isAuthorizedBefore = isAuthorized(authorizer, authorized);
    f(e, args);
    bool isAuthorizedAfter = isAuthorized(authorizer, authorized);

    assert isAuthorizedAfter == isAuthorizedBefore || authorizerIsAuthorized;
}
