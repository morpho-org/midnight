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

    function _.price() external => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;

    // Assumption: token transfers do not revert and do not re-enter Midnight.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

/// HELPERS ///

definition FEE_STEP() returns uint256 = 1000000000000;

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition rawObligationTradingFee(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.obligationState[id].tradingFee0 : index == 1 ? currentContract.obligationState[id].tradingFee1 : index == 2 ? currentContract.obligationState[id].tradingFee2 : index == 3 ? currentContract.obligationState[id].tradingFee3 : index == 4 ? currentContract.obligationState[id].tradingFee4 : index == 5 ? currentContract.obligationState[id].tradingFee5 : currentContract.obligationState[id].tradingFee6;

definition obligationTradingFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(rawObligationTradingFee(id, index) * FEE_STEP());

definition defaultTradingFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultTradingFees[loanToken][index] * FEE_STEP());

/// ROLE SETTER: LIVENESS ///

rule roleSetterCanChangeRoleSetter(env e, address newRoleSetter) {
    require(e.msg.sender == roleSetter(), "caller is the role setter");
    require(e.msg.value == 0, "no ETH sent");

    setRoleSetter@withrevert(e, newRoleSetter);
    assert !lastReverted;
    assert roleSetter() == newRoleSetter;
}

rule roleSetterCanChangeFeeSetter(env e, address newFeeSetter) {
    require(e.msg.sender == roleSetter(), "caller is the role setter");
    require(e.msg.value == 0, "no ETH sent");

    setFeeSetter@withrevert(e, newFeeSetter);
    assert !lastReverted;
    assert feeSetter() == newFeeSetter;
}

rule roleSetterCanChangeFeeClaimer(env e, address newFeeClaimer) {
    require(e.msg.sender == roleSetter(), "caller is the role setter");
    require(e.msg.value == 0, "no ETH sent");

    setFeeClaimer@withrevert(e, newFeeClaimer);
    assert !lastReverted;
    assert feeClaimer() == newFeeClaimer;
}

/// ROLE SETTER: ACCESS CONTROL ///

rule onlyRoleSetterCanChangeRoleSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address before = roleSetter();

    f(e, args);

    assert roleSetter() != before => e.msg.sender == before && f.selector == sig:setRoleSetter(address).selector;
}

rule onlyRoleSetterCanChangeFeeSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address before = feeSetter();
    address roleSetterVal = roleSetter();

    f(e, args);

    assert feeSetter() != before => e.msg.sender == roleSetterVal && f.selector == sig:setFeeSetter(address).selector;
}

rule onlyRoleSetterCanChangeFeeClaimer(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address before = feeClaimer();
    address roleSetterVal = roleSetter();

    f(e, args);

    assert feeClaimer() != before => e.msg.sender == roleSetterVal && f.selector == sig:setFeeClaimer(address).selector;
}

/// FEE SETTER: LIVENESS ///

rule feeSetterCanSetObligationTradingFee(env e, bytes32 id, uint256 index, uint256 newTradingFee) {
    require(e.msg.sender == feeSetter(), "caller is the fee setter");
    require(e.msg.value == 0, "no ETH sent");
    require(index <= 6, "valid fee index");
    require(newTradingFee <= maxTradingFee(index), "fee within bound");
    require(newTradingFee % FEE_STEP() == 0, "fee is a multiple of FEE_STEP");
    require(obligationCreated(id), "obligation exists");

    setObligationTradingFee@withrevert(e, id, index, newTradingFee);
    assert !lastReverted;
    assert obligationTradingFee(id, index) == newTradingFee;
}

rule feeSetterCanSetDefaultTradingFee(env e, address loanToken, uint256 index, uint256 newTradingFee) {
    require(e.msg.sender == feeSetter(), "caller is the fee setter");
    require(e.msg.value == 0, "no ETH sent");
    require(index <= 6, "valid fee index");
    require(newTradingFee <= maxTradingFee(index), "fee within bound");
    require(newTradingFee % FEE_STEP() == 0, "fee is a multiple of FEE_STEP");

    setDefaultTradingFee@withrevert(e, loanToken, index, newTradingFee);
    assert !lastReverted;
    assert defaultTradingFee(loanToken, index) == newTradingFee;
}

rule feeSetterCanSetObligationContinuousFee(env e, bytes32 id, uint256 newContinuousFee) {
    require(e.msg.sender == feeSetter(), "caller is the fee setter");
    require(e.msg.value == 0, "no ETH sent");
    require(newContinuousFee <= MAX_CONTINUOUS_FEE(), "fee within bound");
    require(obligationCreated(id), "obligation exists");

    setObligationContinuousFee@withrevert(e, id, newContinuousFee);
    assert !lastReverted;
    assert to_mathint(continuousFee(id)) == to_mathint(newContinuousFee);
}

rule feeSetterCanSetDefaultContinuousFee(env e, address loanToken, uint256 newContinuousFee) {
    require(e.msg.sender == feeSetter(), "caller is the fee setter");
    require(e.msg.value == 0, "no ETH sent");
    require(newContinuousFee <= MAX_CONTINUOUS_FEE(), "fee within bound");

    setDefaultContinuousFee@withrevert(e, loanToken, newContinuousFee);
    assert !lastReverted;
    assert to_mathint(currentContract.defaultContinuousFee[loanToken]) == to_mathint(newContinuousFee);
}

/// FEE SETTER: ACCESS CONTROL ///
/// Trading fee access control is covered in FeeBoundaries.spec.

rule onlyFeeSetterCanChangeObligationContinuousFee(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require obligationCreated(id);
    uint32 before = continuousFee(id);
    address feeSetterVal = feeSetter();

    f(e, args);

    assert continuousFee(id) != before => e.msg.sender == feeSetterVal && f.selector == sig:setObligationContinuousFee(bytes32, uint256).selector;
}

rule onlyFeeSetterCanChangeDefaultContinuousFee(env e, method f, calldataarg args, address loanToken) filtered { f -> !f.isView } {
    uint32 before = currentContract.defaultContinuousFee[loanToken];
    address feeSetterVal = feeSetter();

    f(e, args);

    assert currentContract.defaultContinuousFee[loanToken] != before => e.msg.sender == feeSetterVal && f.selector == sig:setDefaultContinuousFee(address, uint256).selector;
}

/// FEE CLAIMER: LIVENESS ///
/// Fee claimer access control is covered in OnlyAuthorizedCanChange.spec.

rule feeClaimerCanClaimTradingFee(env e, address token, uint256 amount, address receiver) {
    require(e.msg.sender == feeClaimer(), "caller is the fee claimer");
    require(e.msg.value == 0, "no ETH sent");
    require(amount <= claimableTradingFee(token), "enough claimable balance");

    claimTradingFee@withrevert(e, token, amount, receiver);
    assert !lastReverted;
}

rule feeClaimerCanClaimContinuousFee(env e, Midnight.Obligation obligation, uint256 amount, address receiver) {
    bytes32 id = toId(e, obligation);
    require(e.msg.sender == feeClaimer(), "caller is the fee claimer");
    require(e.msg.value == 0, "no ETH sent");
    require(obligationCreated(id), "obligation exists");
    require(amount <= withdrawable(id), "enough withdrawable");
    require(amount <= totalUnits(id), "enough total units");
    require(amount <= currentContract.obligationState[id].continuousFeeCredit, "enough continuous fee credit");

    claimContinuousFee@withrevert(e, obligation, amount, receiver);
    assert !lastReverted;
}
