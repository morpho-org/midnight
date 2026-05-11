// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function roleSetter() external returns (address) envfree;
    function feeSetter() external returns (address) envfree;
    function feeClaimer() external returns (address) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function claimableTradingFee(address token) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function maxTradingFee(uint256 index) external returns (uint256) envfree;

    // This function is over-approximated, except for the reverting behavior. This is still sound as it is only used inside take but we don't look at the reverting behavior of take in this file.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assumption: token transfers do not revert and do not re-enter Midnight.
    function SafeTransferLib.safeTransfer(address token, address receiver, uint256 amount) internal => cvlSafeTransfer(token, receiver, amount);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 amount) internal => cvlSafeTransferFrom(token, from, to, amount);
}

/// HELPERS ///

definition FEE_STEP() returns uint256 = 10 ^ 12;

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition rawObligationTradingFee(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.obligationState[id].tradingFee0 : index == 1 ? currentContract.obligationState[id].tradingFee1 : index == 2 ? currentContract.obligationState[id].tradingFee2 : index == 3 ? currentContract.obligationState[id].tradingFee3 : index == 4 ? currentContract.obligationState[id].tradingFee4 : index == 5 ? currentContract.obligationState[id].tradingFee5 : currentContract.obligationState[id].tradingFee6;

definition obligationTradingFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(rawObligationTradingFee(id, index) * FEE_STEP());

definition defaultTradingFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultTradingFees[loanToken][index] * FEE_STEP());

ghost mapping(address => mapping(address => mathint)) tokenBalance;

function cvlSafeTransfer(address token, address receiver, uint256 amount) {
    cvlSafeTransferFrom(token, currentContract, receiver, amount);
}

function cvlSafeTransferFrom(address token, address from, address to, uint256 amount) {
    tokenBalance[token][from] = tokenBalance[token][from] - amount;
    tokenBalance[token][to] = tokenBalance[token][to] + amount;
}

/// ROLE SETTER: LIVENESS ///

rule roleSetterCanChangeRoleSetter(env e, address newRoleSetter) {
    address roleSetterBefore = roleSetter();

    setRoleSetter@withrevert(e, newRoleSetter);
    assert !lastReverted <=> e.msg.sender == roleSetterBefore && e.msg.value == 0;
    assert !lastReverted => roleSetter() == newRoleSetter;
}

rule roleSetterCanChangeFeeSetter(env e, address newFeeSetter) {
    address roleSetterBefore = roleSetter();

    setFeeSetter@withrevert(e, newFeeSetter);
    assert !lastReverted <=> e.msg.sender == roleSetterBefore && e.msg.value == 0;
    assert !lastReverted => feeSetter() == newFeeSetter;
}

rule roleSetterCanChangeFeeClaimer(env e, address newFeeClaimer) {
    address roleSetterBefore = roleSetter();

    setFeeClaimer@withrevert(e, newFeeClaimer);
    assert !lastReverted <=> e.msg.sender == roleSetterBefore && e.msg.value == 0;
    assert !lastReverted => feeClaimer() == newFeeClaimer;
}

/// ROLE SETTER: ACCESS CONTROL ///

rule onlyRoleSetterCanChangeRoleSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address roleSetterBefore = roleSetter();

    f(e, args);

    assert roleSetter() != roleSetterBefore => e.msg.sender == roleSetterBefore && f.selector == sig:setRoleSetter(address).selector;
}

rule onlyRoleSetterCanChangeFeeSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address feeSetterBefore = feeSetter();
    address roleSetterBefore = roleSetter();

    f(e, args);

    assert feeSetter() != feeSetterBefore => e.msg.sender == roleSetterBefore && f.selector == sig:setFeeSetter(address).selector;
}

rule onlyRoleSetterCanChangeFeeClaimer(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address feeClaimerBefore = feeClaimer();
    address roleSetterBefore = roleSetter();

    f(e, args);

    assert feeClaimer() != feeClaimerBefore => e.msg.sender == roleSetterBefore && f.selector == sig:setFeeClaimer(address).selector;
}

/// FEE SETTER: LIVENESS ///

rule feeSetterCanSetObligationTradingFee(env e, bytes32 id, uint256 index, uint256 newTradingFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newTradingFee <= maxTradingFee(index) && newTradingFee % FEE_STEP() == 0;
    bool obligationExists = obligationCreated(id);

    setObligationTradingFee@withrevert(e, id, index, newTradingFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee && obligationExists;
    assert !reverted => obligationTradingFee(id, index) == newTradingFee;
}

rule feeSetterCanSetDefaultTradingFee(env e, address loanToken, uint256 index, uint256 newTradingFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newTradingFee <= maxTradingFee(index) && newTradingFee % FEE_STEP() == 0;

    setDefaultTradingFee@withrevert(e, loanToken, index, newTradingFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee;
    assert !reverted => defaultTradingFee(loanToken, index) == newTradingFee;
}

rule feeSetterCanSetObligationContinuousFee(env e, bytes32 id, uint256 newContinuousFee) {
    address feeSetterBefore = feeSetter();
    bool obligationExists = obligationCreated(id);

    setObligationContinuousFee@withrevert(e, id, newContinuousFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && newContinuousFee <= MAX_CONTINUOUS_FEE() && obligationExists;
    assert !reverted => continuousFee(id) == newContinuousFee;
}

rule feeSetterCanSetDefaultContinuousFee(env e, address loanToken, uint256 newContinuousFee) {
    address feeSetterBefore = feeSetter();

    setDefaultContinuousFee@withrevert(e, loanToken, newContinuousFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && newContinuousFee <= MAX_CONTINUOUS_FEE();
    assert !reverted => currentContract.defaultContinuousFee[loanToken] == newContinuousFee;
}

/// FEE SETTER: ACCESS CONTROL ///
/// Trading fee access control is covered in TradingFeeBoundaries.spec.

/// Once an obligation is created, only the fee setter can modify its continuous fees.
rule onlyFeeSetterCanChangeObligationContinuousFeePostCreation(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require obligationCreated(id), "obligation must exist";
    uint32 continuousFeeBefore = continuousFee(id);
    address feeSetterBefore = feeSetter();

    f(e, args);

    assert continuousFee(id) != continuousFeeBefore => e.msg.sender == feeSetterBefore && f.selector == sig:setObligationContinuousFee(bytes32, uint256).selector;
}

rule onlyFeeSetterCanChangeDefaultContinuousFee(env e, method f, calldataarg args, address loanToken) filtered { f -> !f.isView } {
    uint32 defaultContinuousFeeBefore = currentContract.defaultContinuousFee[loanToken];
    address feeSetterBefore = feeSetter();

    f(e, args);

    assert currentContract.defaultContinuousFee[loanToken] != defaultContinuousFeeBefore => e.msg.sender == feeSetterBefore && f.selector == sig:setDefaultContinuousFee(address, uint256).selector;
}

/// FEE CLAIMER: ACCESS CONTROL ///

/// Only the fee claimer can successfully call claimTradingFee.
rule onlyFeeClaimerCanClaimTradingFee(env e, address token, uint256 amount, address receiver) {
    claimTradingFee(e, token, amount, receiver);
    assert e.msg.sender == feeClaimer();
}

/// Only the fee claimer can successfully call claimContinuousFee.
rule onlyFeeClaimerCanClaimContinuousFee(env e, Midnight.Obligation obligation, uint256 amount, address receiver) {
    claimContinuousFee(e, obligation, amount, receiver);
    assert e.msg.sender == feeClaimer();
}

/// FEE CLAIMER: LIVENESS ///

rule feeClaimerCanClaimTradingFee(env e, address token, uint256 amount, address receiver, address user) {
    require user != currentContract && user != receiver;
    address feeClaimerBefore = feeClaimer();
    uint256 claimableBefore = claimableTradingFee(token);
    mathint midnightBalanceBefore = tokenBalance[token][currentContract];
    mathint receiverBalanceBefore = tokenBalance[token][receiver];
    mathint userBalanceBefore = tokenBalance[token][user];

    claimTradingFee@withrevert(e, token, amount, receiver);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeClaimerBefore && e.msg.value == 0 && amount <= claimableBefore;
    assert !reverted => claimableTradingFee(token) == claimableBefore - amount;
    assert !reverted => tokenBalance[token][currentContract] == midnightBalanceBefore - (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[token][receiver] == receiverBalanceBefore + (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[token][user] == userBalanceBefore;
}

rule feeClaimerCanClaimContinuousFee(env e, Midnight.Obligation obligation, uint256 amount, address receiver, address user) {
    require user != currentContract && user != receiver;
    bytes32 id = toId(e, obligation);
    address feeClaimerBefore = feeClaimer();
    bool obligationExists = obligationCreated(id);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 totalUnitsBefore = totalUnits(id);
    uint128 continuousFeeCreditBefore = currentContract.obligationState[id].continuousFeeCredit;
    mathint midnightBalanceBefore = tokenBalance[obligation.loanToken][currentContract];
    mathint receiverBalanceBefore = tokenBalance[obligation.loanToken][receiver];
    mathint userBalanceBefore = tokenBalance[obligation.loanToken][user];

    claimContinuousFee@withrevert(e, obligation, amount, receiver);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeClaimerBefore && e.msg.value == 0 && obligationExists && amount <= withdrawableBefore && amount <= totalUnitsBefore && amount <= continuousFeeCreditBefore;
    assert !reverted => withdrawable(id) == withdrawableBefore - amount;
    assert !reverted => totalUnits(id) == totalUnitsBefore - amount;
    assert !reverted => currentContract.obligationState[id].continuousFeeCredit == continuousFeeCreditBefore - amount;
    assert !reverted => tokenBalance[obligation.loanToken][currentContract] == midnightBalanceBefore - (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[obligation.loanToken][receiver] == receiverBalanceBefore + (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[obligation.loanToken][user] == userBalanceBefore;
}
