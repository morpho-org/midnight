// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function Utils.toId(Midnight.Market) external returns (bytes32) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function configurator() external returns (address) envfree;
    function feeSetter() external returns (address) envfree;
    function feeClaimer() external returns (address) envfree;
    function tickSpacingSetter() external returns (address) envfree;
    function isLltvEnabled(uint256 lltv) external returns (bool) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function claimableSettlementFee(address token) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function Utils.maxSettlementFee(uint256 index) external returns (uint256) envfree;

    // This function is over-approximated, except for the reverting behavior. This is still sound as it is only used inside take but we don't look at the reverting behavior of take in this file.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Summarize mulDivDown and mulDivUp by deterministic ghost functions (also modelling reverts).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // msb is over-approximated by a nondeterministic value.
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;

    // Assume that tokens do not reenter and do not revert: this is justified as we verify properties about the function's bodies.
    function SafeTransferLib.safeTransfer(address token, address receiver, uint256 amount) internal => cvlSafeTransfer(token, receiver, amount);
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 amount) internal => cvlSafeTransferFrom(token, from, to, amount);
}

/// HELPERS ///

definition WAD() returns uint256 = 10 ^ 18;

definition CBP() returns uint256 = 10 ^ 12;

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition marketSettlementFeeCbp(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.marketState[id].settlementFeeCbp0 : index == 1 ? currentContract.marketState[id].settlementFeeCbp1 : index == 2 ? currentContract.marketState[id].settlementFeeCbp2 : index == 3 ? currentContract.marketState[id].settlementFeeCbp3 : index == 4 ? currentContract.marketState[id].settlementFeeCbp4 : index == 5 ? currentContract.marketState[id].settlementFeeCbp5 : currentContract.marketState[id].settlementFeeCbp6;

definition marketSettlementFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(marketSettlementFeeCbp(id, index) * CBP());

definition defaultSettlementFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultSettlementFeeCbp[loanToken][index] * CBP());

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

ghost mapping(address => mapping(address => mathint)) tokenBalance;

function cvlSafeTransfer(address token, address receiver, uint256 amount) {
    cvlSafeTransferFrom(token, currentContract, receiver, amount);
}

function cvlSafeTransferFrom(address token, address from, address to, uint256 amount) {
    tokenBalance[token][from] = tokenBalance[token][from] - amount;
    tokenBalance[token][to] = tokenBalance[token][to] + amount;
}

function marketIsCreated(bytes32 id) returns (bool) {
    return tickSpacing(id) > 0;
}

/// CONFIGURATOR: LIVENESS ///

rule configuratorCanChangeConfigurator(env e, address newConfigurator) {
    address configuratorBefore = configurator();

    setConfigurator@withrevert(e, newConfigurator);
    assert !lastReverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0;
    assert !lastReverted => configurator() == newConfigurator;
}

rule configuratorCanChangeFeeSetter(env e, address newFeeSetter) {
    address configuratorBefore = configurator();

    setFeeSetter@withrevert(e, newFeeSetter);
    assert !lastReverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0;
    assert !lastReverted => feeSetter() == newFeeSetter;
}

rule configuratorCanChangeFeeClaimer(env e, address newFeeClaimer) {
    address configuratorBefore = configurator();

    setFeeClaimer@withrevert(e, newFeeClaimer);
    assert !lastReverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0;
    assert !lastReverted => feeClaimer() == newFeeClaimer;
}

rule configuratorCanChangeTickSpacingSetter(env e, address newTickSpacingSetter) {
    address configuratorBefore = configurator();

    setTickSpacingSetter@withrevert(e, newTickSpacingSetter);
    assert !lastReverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0;
    assert !lastReverted => tickSpacingSetter() == newTickSpacingSetter;
}

rule configuratorCanEnableLltv(env e, uint256 lltv) {
    address configuratorBefore = configurator();

    enableLltv@withrevert(e, lltv);
    assert !lastReverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0 && lltv <= WAD();
    assert !lastReverted => isLltvEnabled(lltv);
}

/// CONFIGURATOR: ACCESS CONTROL ///

rule onlyConfiguratorCanChangeConfigurator(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address configuratorBefore = configurator();

    f(e, args);

    assert configurator() != configuratorBefore => e.msg.sender == configuratorBefore && f.selector == sig:setConfigurator(address).selector;
}

rule onlyConfiguratorCanChangeFeeSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address feeSetterBefore = feeSetter();
    address configuratorBefore = configurator();

    f(e, args);

    assert feeSetter() != feeSetterBefore => e.msg.sender == configuratorBefore && f.selector == sig:setFeeSetter(address).selector;
}

rule onlyConfiguratorCanChangeFeeClaimer(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address feeClaimerBefore = feeClaimer();
    address configuratorBefore = configurator();

    f(e, args);

    assert feeClaimer() != feeClaimerBefore => e.msg.sender == configuratorBefore && f.selector == sig:setFeeClaimer(address).selector;
}

rule onlyConfiguratorCanChangeTickSpacingSetter(env e, method f, calldataarg args) filtered { f -> !f.isView } {
    address tickSpacingSetterBefore = tickSpacingSetter();
    address configuratorBefore = configurator();

    f(e, args);

    assert tickSpacingSetter() != tickSpacingSetterBefore => e.msg.sender == configuratorBefore && f.selector == sig:setTickSpacingSetter(address).selector;
}

/// LLTV TIERS: ACCESS CONTROL ///

/// Enabled LLTV tiers can only be enabled by the configurator, and never removed.
rule onlyConfiguratorCanEnableLltv(env e, method f, calldataarg args, uint256 lltv) filtered { f -> !f.isView } {
    bool enabledBefore = isLltvEnabled(lltv);
    address configuratorBefore = configurator();

    f(e, args);

    assert isLltvEnabled(lltv) != enabledBefore => enabledBefore == false && e.msg.sender == configuratorBefore && f.selector == sig:enableLltv(uint256).selector;
}

/// LIQUIDATION CURSORS: LIVENESS ///

rule configuratorCanEnableLiquidationCursor(env e, uint256 liquidationCursor) {
    address configuratorBefore = configurator();

    enableLiquidationCursor@withrevert(e, liquidationCursor);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == configuratorBefore && e.msg.value == 0 && liquidationCursor < WAD();
    assert !reverted => currentContract.isLiquidationCursorEnabled[liquidationCursor];
}

/// LIQUIDATION CURSORS: ACCESS CONTROL ///

/// Only the configurator can enable a liquidationCursor, and only through enableLiquidationCursor.
rule onlyConfiguratorCanEnableLiquidationCursor(env e, method f, calldataarg args, uint256 liquidationCursor) filtered { f -> !f.isView } {
    bool enabledBefore = currentContract.isLiquidationCursorEnabled[liquidationCursor];
    address configuratorBefore = configurator();

    f(e, args);

    assert currentContract.isLiquidationCursorEnabled[liquidationCursor] != enabledBefore => e.msg.sender == configuratorBefore && f.selector == sig:enableLiquidationCursor(uint256).selector;
}

/// LiquidationCursors can only be enabled, never disabled.
rule liquidationCursorsOnlyGrow(env e, method f, calldataarg args, uint256 liquidationCursor) filtered { f -> !f.isView } {
    bool enabledBefore = currentContract.isLiquidationCursorEnabled[liquidationCursor];

    f(e, args);

    assert enabledBefore => currentContract.isLiquidationCursorEnabled[liquidationCursor];
}

/// Every enabled liquidationCursor is strictly below WAD.
strong invariant liquidationCursorsBelowOne(uint256 liquidationCursor)
    currentContract.isLiquidationCursorEnabled[liquidationCursor] => liquidationCursor < WAD();

/// FEE SETTER: LIVENESS ///

rule feeSetterCanSetMarketSettlementFee(env e, bytes32 id, uint256 index, uint256 newSettlementFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newSettlementFee <= Utils.maxSettlementFee(index) && newSettlementFee % CBP() == 0;
    bool marketIsCreated = marketIsCreated(id);

    setMarketSettlementFee@withrevert(e, id, index, newSettlementFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee && marketIsCreated;
    assert !reverted => marketSettlementFee(id, index) == newSettlementFee;
}

rule feeSetterCanSetDefaultSettlementFee(env e, address loanToken, uint256 index, uint256 newSettlementFee) {
    address feeSetterBefore = feeSetter();
    bool validIndex = index <= 6;
    bool validFee = validIndex && newSettlementFee <= Utils.maxSettlementFee(index) && newSettlementFee % CBP() == 0;

    setDefaultSettlementFee@withrevert(e, loanToken, index, newSettlementFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && validFee;
    assert !reverted => defaultSettlementFee(loanToken, index) == newSettlementFee;
}

rule feeSetterCanSetMarketContinuousFee(env e, bytes32 id, uint256 newContinuousFee) {
    address feeSetterBefore = feeSetter();
    bool marketIsCreated = marketIsCreated(id);

    setMarketContinuousFee@withrevert(e, id, newContinuousFee);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeSetterBefore && e.msg.value == 0 && newContinuousFee <= MAX_CONTINUOUS_FEE() && marketIsCreated;
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
/// Settlement fee access control is covered in SettlementFeeBoundaries.spec.

/// Once a market is created, only the fee setter can modify its continuous fees.
rule onlyFeeSetterCanChangeMarketContinuousFeePostCreation(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require marketIsCreated(id), "market must exist";
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
    bool marketIsCreated = marketIsCreated(id);
    uint8 tickSpacingBefore = tickSpacing(id);
    bool validNewTickSpacing = newTickSpacing > 0 && tickSpacingBefore % newTickSpacing == 0;

    setMarketTickSpacing@withrevert(e, id, newTickSpacing);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == tickSpacingSetterBefore && e.msg.value == 0 && marketIsCreated && validNewTickSpacing;
    assert !reverted => to_mathint(tickSpacing(id)) == to_mathint(newTickSpacing);
}

/// TICK SPACING SETTER: ACCESS CONTROL ///

/// Once a market is created, only the tick spacing setter can modify its tick spacing.
rule onlyTickSpacingSetterCanChangeMarketTickSpacingPostCreation(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView } {
    require marketIsCreated(id), "market must exist";
    uint8 tickSpacingBefore = tickSpacing(id);
    address tickSpacingSetterBefore = tickSpacingSetter();

    f(e, args);

    assert tickSpacing(id) != tickSpacingBefore => e.msg.sender == tickSpacingSetterBefore && f.selector == sig:setMarketTickSpacing(bytes32, uint256).selector;
}

/// FEE CLAIMER: ACCESS CONTROL ///

/// Only the fee claimer can successfully call claimSettlementFee.
rule onlyFeeClaimerCanClaimSettlementFee(env e, address token, uint256 amount, address receiver) {
    claimSettlementFee(e, token, amount, receiver);
    assert e.msg.sender == feeClaimer();
}

/// Only the fee claimer can successfully call claimContinuousFee.
rule onlyFeeClaimerCanClaimContinuousFee(env e, Midnight.Market market, uint256 amount, address receiver) {
    claimContinuousFee(e, market, amount, receiver);
    assert e.msg.sender == feeClaimer();
}

/// FEE CLAIMER: LIVENESS ///

rule feeClaimerCanClaimSettlementFee(env e, address token, uint256 amount, address receiver, address user) {
    address feeClaimerBefore = feeClaimer();
    uint256 claimableBefore = claimableSettlementFee(token);
    mathint midnightBalanceBefore = tokenBalance[token][currentContract];
    mathint receiverBalanceBefore = tokenBalance[token][receiver];
    mathint userBalanceBefore = tokenBalance[token][user];

    claimSettlementFee@withrevert(e, token, amount, receiver);
    bool reverted = lastReverted;
    assert !reverted <=> e.msg.sender == feeClaimerBefore && e.msg.value == 0 && amount <= claimableBefore;
    assert !reverted => claimableSettlementFee(token) == claimableBefore - amount;
    assert !reverted => tokenBalance[token][currentContract] == midnightBalanceBefore - (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[token][receiver] == receiverBalanceBefore + (receiver == currentContract ? 0 : amount);
    assert !reverted => user != currentContract && user != receiver => tokenBalance[token][user] == userBalanceBefore;
}

rule feeClaimerCanClaimContinuousFee(env e, Midnight.Market market, uint256 amount, address receiver, address user) {
    bytes32 id = Utils.toId(market);
    address feeClaimerBefore = feeClaimer();
    bool marketWasCreated = marketIsCreated(id);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 totalUnitsBefore = totalUnits(id);
    uint128 continuousFeeCreditBefore = currentContract.marketState[id].continuousFeeCredit;
    mathint midnightBalanceBefore = tokenBalance[market.loanToken][currentContract];
    mathint receiverBalanceBefore = tokenBalance[market.loanToken][receiver];
    mathint userBalanceBefore = tokenBalance[market.loanToken][user];

    claimContinuousFee@withrevert(e, market, amount, receiver);
    bool reverted = lastReverted;
    assert !reverted => e.msg.sender == feeClaimerBefore && e.msg.value == 0 && amount <= withdrawableBefore && amount <= totalUnitsBefore && amount <= continuousFeeCreditBefore;
    assert marketWasCreated && e.msg.sender == feeClaimerBefore && e.msg.value == 0 && amount <= withdrawableBefore && amount <= totalUnitsBefore && amount <= continuousFeeCreditBefore => !reverted;
    assert !reverted => withdrawable(id) == withdrawableBefore - amount;
    assert !reverted => totalUnits(id) == totalUnitsBefore - amount;
    assert !reverted => currentContract.marketState[id].continuousFeeCredit == continuousFeeCreditBefore - amount;
    assert !reverted => tokenBalance[market.loanToken][currentContract] == midnightBalanceBefore - (receiver == currentContract ? 0 : amount);
    assert !reverted => tokenBalance[market.loanToken][receiver] == receiverBalanceBefore + (receiver == currentContract ? 0 : amount);
    assert !reverted => user != currentContract && user != receiver => tokenBalance[market.loanToken][user] == userBalanceBefore;
}
