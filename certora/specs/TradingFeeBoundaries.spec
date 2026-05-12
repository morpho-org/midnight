// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function toId(Midnight.Obligation) external returns (bytes32) envfree;
    function Utils.maxTradingFee(uint256 index) external returns (uint256) envfree;

    // Over-approximate view functions for prover performance.
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

/// Breakpoint time in seconds for index 0..6, mirroring the tradingFee intervals in Midnight.sol.
definition breakpointTime(uint256 index) returns uint256 = index == 0 ? 0 : index == 1 ? 86400 : index == 2 ? 7 * 86400 : index == 3 ? 30 * 86400 : index == 4 ? 90 * 86400 : index == 5 ? 180 * 86400 : index == 6 ? 360 * 86400 : 0;

/// Lower enclosing breakpoint index for a given time-to-maturity.
definition lowerIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 5 : ttm >= breakpointTime(4) ? 4 : ttm >= breakpointTime(3) ? 3 : ttm >= breakpointTime(2) ? 2 : ttm >= breakpointTime(1) ? 1 : 0;

/// Upper enclosing breakpoint index for a given time-to-maturity.
definition upperIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 6 : ttm >= breakpointTime(4) ? 5 : ttm >= breakpointTime(3) ? 4 : ttm >= breakpointTime(2) ? 3 : ttm >= breakpointTime(1) ? 2 : 1;

definition FEE_STEP() returns uint256 = 10 ^ 12;

definition defaultTradingFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultTradingFees[loanToken][index] * FEE_STEP());

definition rawObligationTradingFee(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.obligationState[id].tradingFee0 : index == 1 ? currentContract.obligationState[id].tradingFee1 : index == 2 ? currentContract.obligationState[id].tradingFee2 : index == 3 ? currentContract.obligationState[id].tradingFee3 : index == 4 ? currentContract.obligationState[id].tradingFee4 : index == 5 ? currentContract.obligationState[id].tradingFee5 : currentContract.obligationState[id].tradingFee6;

definition obligationTradingFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(rawObligationTradingFee(id, index) * FEE_STEP());

/// Default trading fees for any loan token at each index are bounded by its specific maxTradingFee cap.
invariant defaultTradingFeePerIndexBound(address loanToken, uint256 index)
    index <= 6 => defaultTradingFee(loanToken, index) <= Utils.maxTradingFee(index);

/// Every obligation's trading fee breakpoints are bounded by the per-index maximum.
invariant obligationTradingFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => obligationTradingFee(id, index) <= Utils.maxTradingFee(index)
    {
        preserved touchObligation(Midnight.Obligation obligation) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved withdraw(Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved repay(Midnight.Obligation obligation, uint256 units, address onBehalf, address callback, bytes data) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved supplyCollateral(Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved withdrawCollateral(Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved liquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(obligation.loanToken, index);
        }
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData) with (env e) {
            requireInvariant defaultTradingFeePerIndexBound(offer.obligation.loanToken, index);
        }
    }

/// When an obligation is created, its trading fees are set to the default trading fees of its loan token.
rule newObligationTradingFeesMatchDefault(env e, Midnight.Obligation obligation, uint256 index) {
    require index <= 6, "index out of bounds";
    bytes32 id = toId(e, obligation);
    require !obligationCreated(id), "obligation not yet created";

    uint256 expectedTradingFee = defaultTradingFee(obligation.loanToken, index);

    touchObligation(e, obligation);

    assert obligationTradingFee(id, index) == expectedTradingFee;
}

/// Only the fee setter can modify default trading fees (multicall is DELETEd and not checked here).
rule onlyFeeSetterCanChangeDefaultTradingFees(method f, env e, address token, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    uint256 defaultTradingFeeBefore = defaultTradingFee(token, index);
    calldataarg args;
    f(e, args);
    assert defaultTradingFee(token, index) != defaultTradingFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setDefaultTradingFee(address, uint256, uint256).selector;
}

/// Once an obligation is created, only the fee setter can modify its trading fees.
rule onlyFeeSetterCanChangeObligationTradingFeesPostCreation(method f, env e, bytes32 id, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    require obligationCreated(id), "assume that the obligation is created";
    uint256 obligationTradingFeeBefore = obligationTradingFee(id, index);
    calldataarg args;
    f(e, args);

    assert obligationTradingFee(id, index) != obligationTradingFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setObligationTradingFee(bytes32, uint256, uint256).selector;
}

/// The trading fee at a breakpoint is equal to the trading fee state variable at that index.
rule tradingFeeAtBreakpoint(bytes32 id, uint256 index) {
    assert index <= 6 => tradingFee(id, breakpointTime(index)) == obligationTradingFee(id, index);
}

/// For any time-to-maturity the trading fee is enclosed between the two adjacent breakpoint values (never overshoots or undershoots).
rule tradingFeeIsBoundedByBreakpointFees(bytes32 id, uint256 timeToMaturity) {
    uint256 tradingFeeLo = obligationTradingFee(id, lowerIndex(timeToMaturity));
    uint256 tradingFeeHi = obligationTradingFee(id, upperIndex(timeToMaturity));
    uint256 fee = tradingFee(id, timeToMaturity);

    assert (tradingFeeLo <= tradingFeeHi) => (fee >= tradingFeeLo && fee <= tradingFeeHi);
    assert (tradingFeeHi <= tradingFeeLo) => (fee >= tradingFeeHi && fee <= tradingFeeLo);
}
