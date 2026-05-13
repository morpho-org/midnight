// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function roleSetter() external returns (address) envfree;
    function feeSetter() external returns (address) envfree;
    function feeClaimer() external returns (address) envfree;
    function tickSpacingSetter() external returns (address) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function claimableTradingFee(address token) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function Utils.maxTradingFee(uint256 index) external returns (uint256) envfree;

    // This function is over-approximated, except for the reverting behavior. This is still sound as it is only used inside take but we don't look at the reverting behavior of take in this file.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assumption: token transfers do not revert and do not re-enter Midnight.
    function SafeTransferLib.safeTransfer(address token, address receiver, uint256 amount) internal => cvlSafeTransfer(token, receiver, amount);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 amount) internal => cvlSafeTransferFrom(token, from, to, amount);
}

/// HELPERS ///

definition CBP() returns uint256 = 10 ^ 12;

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition marketTradingFeeCbp(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.marketState[id].tradingFeeCbp0 : index == 1 ? currentContract.marketState[id].tradingFeeCbp1 : index == 2 ? currentContract.marketState[id].tradingFeeCbp2 : index == 3 ? currentContract.marketState[id].tradingFeeCbp3 : index == 4 ? currentContract.marketState[id].tradingFeeCbp4 : index == 5 ? currentContract.marketState[id].tradingFeeCbp5 : currentContract.marketState[id].tradingFeeCbp6;

definition marketTradingFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(marketTradingFeeCbp(id, index) * CBP());

definition defaultTradingFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultTradingFeeCbp[loanToken][index] * CBP());

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

rule roleSetterCanChangeTickSpacingSetter(env e, address newTickSpacingSetter) {
    address roleSetterBefore = roleSetter();

    setTickSpacingSetter@withrevert(e, newTickSpacingSetter);
    assert !lastReverted <=> e.msg.sender == roleSetterBefore && e.msg.value == 0;
    assert !lastReverted => tickSpacingSetter() == newTickSpacingSetter;
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

rule onlyRoleSetterCanChangeTickSpacingSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address tickSpacingSetterBefore = tickSpacingSetter();
    address roleSetterBefore = roleSetter();

    f(e, args);

    assert tickSpacingSetter() != tickSpacingSetterBefore => e.msg.sender == roleSetterBefore && f.selector == sig:setTickSpacingSetter(address).selector;
}

/// FEE SETTER: LIVENESS ///

rule feeSetterCanSetMarketTradingFee(env e, bytes32 id, uint256 index, uint256 newTradingFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newTradingFee <= Utils.maxTradingFee(index) && newTradingFee % CBP() == 0;
    bool marketExists = tickSpacing(id) > 0;

    setMarketTradingFee@withrevert(e, id, index, newTradingFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee && marketExists;
    assert !reverted => marketTradingFee(id, index) == newTradingFee;
}

rule feeSetterCanSetDefaultTradingFee(env e, address loanToken, uint256 index, uint256 newTradingFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newTradingFee <= Utils.maxTradingFee(index) && newTradingFee % CBP() == 0;

    setDefaultTradingFee@withrevert(e, loanToken, index, newTradingFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee;
    assert !reverted => defaultTradingFee(loanToken, index) == newTradingFee;
}

rule feeSetterCanSetMarketContinuousFee(env e, bytes32 id, uint256 newContinuousFee) {
    address feeSetterBefore = feeSetter();
    bool marketExists = tickSpacing(id) > 0;

    setMarketContinuousFee@withrevert(e, id, newContinuousFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && newContinuousFee <= MAX_CONTINUOUS_FEE() && marketExists;
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

/// Once a market is created, only the fee setter can modify its continuous fees.
rule onlyFeeSetterCanChangeMarketContinuousFeePostCreation(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require tickSpacing(id) > 0, "market must exist";
    uint32 continuousFeeBefore = continuousFee(id);
    address feeSetterBefore = feeSetter();

    f(e, args);

    assert continuousFee(id) != continuousFeeBefore => e.msg.sender == feeSetterBefore && f.selector == sig:setMarketContinuousFee(bytes32, uint256).selector;
}

rule onlyFeeSetterCanChangeDefaultContinuousFee(env e, method f, calldataarg args, address loanToken) filtered { f -> !f.isView } {
    uint32 defaultContinuousFeeBefore = currentContract.defaultContinuousFee[loanToken];
    address feeSetterBefore = feeSetter();

    f(e, args);

    assert currentContract.defaultContinuousFee[loanToken] != defaultContinuousFeeBefore => e.msg.sender == feeSetterBefore && f.selector == sig:setDefaultContinuousFee(address, uint256).selector;
}

/// TICK SPACING SETTER: LIVENESS ///

rule tickSpacingSetterCanSetMarketTickSpacing(env e, bytes32 id, uint256 newTickSpacing) {
    address tickSpacingSetterBefore = tickSpacingSetter();
    bool marketExists = tickSpacing(id) > 0;
    uint8 tickSpacingBefore = tickSpacing(id);
    bool validNewTickSpacing = newTickSpacing > 0 && tickSpacingBefore % newTickSpacing == 0;

    setMarketTickSpacing@withrevert(e, id, newTickSpacing);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == tickSpacingSetterBefore && e.msg.value == 0 && marketExists && validNewTickSpacing;
    assert !reverted => to_mathint(tickSpacing(id)) == to_mathint(newTickSpacing);
}

/// TICK SPACING SETTER: ACCESS CONTROL ///

/// Once a market is created, only the tick spacing setter can modify its tick spacing.
rule onlyTickSpacingSetterCanChangeMarketTickSpacingPostCreation(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require tickSpacing(id) > 0, "market must exist";
    uint8 tickSpacingBefore = tickSpacing(id);
    address tickSpacingSetterBefore = tickSpacingSetter();

    f(e, args);

    assert tickSpacing(id) != tickSpacingBefore => e.msg.sender == tickSpacingSetterBefore && f.selector == sig:setMarketTickSpacing(bytes32, uint256).selector;
}

/// FEE CLAIMER: ACCESS CONTROL ///

/// Only the fee claimer can successfully call claimTradingFee.
rule onlyFeeClaimerCanClaimTradingFee(env e, address token, uint256 amount, address receiver) {
    claimTradingFee(e, token, amount, receiver);
    assert e.msg.sender == feeClaimer();
}

/// Only the fee claimer can successfully call claimContinuousFee.
rule onlyFeeClaimerCanClaimContinuousFee(env e, Midnight.Market market, uint256 amount, address receiver) {
    claimContinuousFee(e, market, amount, receiver);
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

rule feeClaimerCanClaimContinuousFee(env e, Midnight.Market market, uint256 amount, address receiver, address user) {
    require user != currentContract && user != receiver;
    bytes32 id = toId(e, market);
    address feeClaimerBefore = feeClaimer();
    bool marketExists = tickSpacing(id) > 0;
    uint256 withdrawableBefore = withdrawable(id);
    uint256 totalUnitsBefore = totalUnits(id);
    uint128 continuousFeeCreditBefore = currentContract.marketState[id].continuousFeeCredit;
    mathint midnightBalanceBefore = tokenBalance[market.loanToken][currentContract];
    mathint receiverBalanceBefore = tokenBalance[market.loanToken][receiver];
    mathint userBalanceBefore = tokenBalance[market.loanToken][user];

    claimContinuousFee@withrevert(e, market, amount, receiver);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeClaimerBefore && e.msg.value == 0 && marketExists && amount <= withdrawableBefore && amount <= totalUnitsBefore && amount <= continuousFeeCreditBefore;
    assert !reverted => withdrawable(id) == withdrawableBefore - amount;
    assert !reverted => totalUnits(id) == totalUnitsBefore - amount;
    assert !reverted => currentContract.marketState[id].continuousFeeCredit == continuousFeeCreditBefore - amount;
    assert !reverted => tokenBalance[market.loanToken][currentContract] == midnightBalanceBefore - (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[market.loanToken][receiver] == receiverBalanceBefore + (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[market.loanToken][user] == userBalanceBefore;
}
