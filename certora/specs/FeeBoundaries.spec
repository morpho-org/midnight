// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function maxTradingFee(uint256 index) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function toId(Midnight.Obligation) external returns (bytes32) envfree;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
}

/// Breakpoint time in seconds for index 0..6, mirroring the tradingFee intervals in Midnight.sol.
definition breakpointTime(uint256 index) returns uint256 = index == 0 ? 0 : index == 1 ? 86400 : index == 2 ? 7 * 86400 : index == 3 ? 30 * 86400 : index == 4 ? 90 * 86400 : index == 5 ? 180 * 86400 : index == 6 ? 360 * 86400 : 0;

/// Lower enclosing breakpoint index for a given time-to-maturity.
definition lowerIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 5 : ttm >= breakpointTime(4) ? 4 : ttm >= breakpointTime(3) ? 3 : ttm >= breakpointTime(2) ? 2 : ttm >= breakpointTime(1) ? 1 : 0;

/// Upper enclosing breakpoint index for a given time-to-maturity.
definition upperIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 6 : ttm >= breakpointTime(4) ? 5 : ttm >= breakpointTime(3) ? 4 : ttm >= breakpointTime(2) ? 3 : ttm >= breakpointTime(1) ? 2 : 1;

definition FEE_STEP() returns uint256 = 1000000000000;

definition defaultFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultTradingFees[loanToken][index] * FEE_STEP());

definition rawObligationFee(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.obligationState[id].fee0 : index == 1 ? currentContract.obligationState[id].fee1 : index == 2 ? currentContract.obligationState[id].fee2 : index == 3 ? currentContract.obligationState[id].fee3 : index == 4 ? currentContract.obligationState[id].fee4 : index == 5 ? currentContract.obligationState[id].fee5 : currentContract.obligationState[id].fee6;

definition obligationFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(rawObligationFee(id, index) * FEE_STEP());

/// Default fees for any loan token at each index are bounded by its specific maxTradingFee cap.
invariant defaultFeePerIndexBound(address loanToken, uint256 index)
    index <= 6 => defaultFee(loanToken, index) <= maxTradingFee(index);

/// Every obligation's fee breakpoints are bounded by the per-index maximum.
invariant obligationFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => obligationFee(id, index) <= maxTradingFee(index)
    {
        preserved touchObligation(Midnight.Obligation obligation) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved withdraw(Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved repay(Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved supplyCollateral(Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved withdrawCollateral(Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved liquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) with (env e) {
            requireInvariant defaultFeePerIndexBound(obligation.loanToken, index);
        }
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) with (env e) {
            requireInvariant defaultFeePerIndexBound(offer.obligation.loanToken, index);
        }
    }

/// When an obligation is created, its fees are set to the default fees of its loan token.
rule newObligationFeesMatchDefault(env e, Midnight.Obligation obligation, uint256 index) {
    require index <= 6, "index out of bounds";
    bytes32 id = toId(e, obligation);
    require !obligationCreated(id), "obligation not yet created";

    uint256 expectedFee = defaultFee(obligation.loanToken, index);

    touchObligation(e, obligation);

    assert obligationFee(id, index) == expectedFee;
}

/// Only the fee setter can modify default fees (multicall is DELETEd and not checked here).
rule onlyFeeSetterCanChangeDefaultFees(method f, env e, address token, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    uint256 defaultFeeBefore = defaultFee(token, index);
    calldataarg args;
    f(e, args);
    assert defaultFee(token, index) != defaultFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setDefaultTradingFee(address, uint256, uint256).selector;
}

/// Once an obligation is created, only the fee setter can modify its fees.
rule onlyFeeSetterCanChangeObligationFeesPostCreation(method f, env e, bytes32 id, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    require obligationCreated(id), "assume that the obligation is created";
    uint256 obligationFeeBefore = obligationFee(id, index);
    calldataarg args;
    f(e, args);

    assert obligationFee(id, index) != obligationFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setObligationTradingFee(bytes32, uint256, uint256).selector;
}

/// The trading fee at a breakpoint is equal to the fee state variable at that index.
rule tradingFeeAtBreakpoint(bytes32 id, uint256 index) {
    assert index <= 6 => tradingFee(id, breakpointTime(index)) == obligationFee(id, index);
}

/// For any time-to-maturity the trading fee is enclosed between the two adjacent breakpoint values (never overshoots or undershoots).
rule tradingFeeIsBoundedByBreakpointFees(bytes32 id, uint256 timeToMaturity) {
    uint256 feeLo = obligationFee(id, lowerIndex(timeToMaturity));
    uint256 feeHi = obligationFee(id, upperIndex(timeToMaturity));
    uint256 fee = tradingFee(id, timeToMaturity);

    assert (feeLo <= feeHi) => (fee >= feeLo && fee <= feeHi);
    assert (feeHi <= feeLo) => (fee >= feeHi && fee <= feeLo);
}
