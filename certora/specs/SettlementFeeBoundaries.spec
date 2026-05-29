// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function settlementFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function toId(Midnight.Market) external returns (bytes32) envfree;
    function Utils.maxSettlementFee(uint256 index) external returns (uint256) envfree;

    // Over-approximate view functions.
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
}

/// Breakpoint time in seconds for index 0..6, mirroring the settlementFee intervals in Midnight.sol.
definition breakpointTime(uint256 index) returns uint256 = index == 0 ? 0 : index == 1 ? 86400 : index == 2 ? 7 * 86400 : index == 3 ? 30 * 86400 : index == 4 ? 90 * 86400 : index == 5 ? 180 * 86400 : index == 6 ? 360 * 86400 : 0;

/// Lower enclosing breakpoint index for a given time-to-maturity.
definition lowerIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 5 : ttm >= breakpointTime(4) ? 4 : ttm >= breakpointTime(3) ? 3 : ttm >= breakpointTime(2) ? 2 : ttm >= breakpointTime(1) ? 1 : 0;

/// Upper enclosing breakpoint index for a given time-to-maturity.
definition upperIndex(uint256 ttm) returns uint256 = ttm >= breakpointTime(6) ? 6 : ttm >= breakpointTime(5) ? 6 : ttm >= breakpointTime(4) ? 5 : ttm >= breakpointTime(3) ? 4 : ttm >= breakpointTime(2) ? 3 : ttm >= breakpointTime(1) ? 2 : 1;

definition CBP() returns uint256 = 10 ^ 12;

definition defaultSettlementFee(address loanToken, uint256 index) returns uint256 = assert_uint256(currentContract.defaultSettlementFeeCbp[loanToken][index] * CBP());

definition marketSettlementFeeCbp(bytes32 id, uint256 index) returns uint16 = index == 0 ? currentContract.marketState[id].settlementFeeCbp0 : index == 1 ? currentContract.marketState[id].settlementFeeCbp1 : index == 2 ? currentContract.marketState[id].settlementFeeCbp2 : index == 3 ? currentContract.marketState[id].settlementFeeCbp3 : index == 4 ? currentContract.marketState[id].settlementFeeCbp4 : index == 5 ? currentContract.marketState[id].settlementFeeCbp5 : currentContract.marketState[id].settlementFeeCbp6;

definition marketSettlementFee(bytes32 id, uint256 index) returns uint256 = assert_uint256(marketSettlementFeeCbp(id, index) * CBP());

/// Default settlement fees for any loan token at each index are bounded by its specific maxSettlementFee cap.
invariant defaultSettlementFeePerIndexBound(address loanToken, uint256 index)
    index <= 6 => defaultSettlementFee(loanToken, index) <= Utils.maxSettlementFee(index);

/// Every market's settlement fee breakpoints are bounded by the per-index maximum.
invariant marketSettlementFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => marketSettlementFee(id, index) <= Utils.maxSettlementFee(index)
    {
        preserved touchMarket(Midnight.Market market) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved withdraw(Midnight.Market market, uint256 units, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved repay(Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved supplyCollateral(Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved withdrawCollateral(Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved liquidate(Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(market.loanToken, index);
        }
        preserved take(Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) with (env e) {
            requireInvariant defaultSettlementFeePerIndexBound(offer.market.loanToken, index);
        }
    }

/// When a market is created, its settlement fees are set to the default settlement fees of its loan token.
rule newMarketSettlementFeesMatchDefault(env e, Midnight.Market market, uint256 index) {
    require index <= 6, "index out of bounds";
    bytes32 id = toId(e, market);
    require tickSpacing(id) == 0, "market not yet created";

    uint256 expectedSettlementFee = defaultSettlementFee(market.loanToken, index);

    touchMarket(e, market);

    assert marketSettlementFee(id, index) == expectedSettlementFee;
}

/// Only the fee setter can modify default settlement fees (multicall is DELETEd and not checked here).
rule onlyFeeSetterCanChangeDefaultSettlementFees(method f, env e, address token, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    uint256 defaultSettlementFeeBefore = defaultSettlementFee(token, index);
    calldataarg args;
    f(e, args);
    assert defaultSettlementFee(token, index) != defaultSettlementFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setDefaultSettlementFee(address, uint256, uint256).selector;
}

/// Once a market is created, only the fee setter can modify its settlement fees.
rule onlyFeeSetterCanChangeMarketSettlementFeesPostCreation(method f, env e, bytes32 id, uint256 index) filtered { f -> !f.isView } {
    require index <= 6, "index out of bounds";
    require tickSpacing(id) > 0, "assume that the market is created";
    uint256 marketSettlementFeeBefore = marketSettlementFee(id, index);
    calldataarg args;
    f(e, args);

    assert marketSettlementFee(id, index) != marketSettlementFeeBefore => e.msg.sender == currentContract.feeSetter() && f.selector == sig:setMarketSettlementFee(bytes32, uint256, uint256).selector;
}

/// The settlement fee at a breakpoint is equal to the settlement fee state variable at that index.
rule settlementFeeAtBreakpoint(bytes32 id, uint256 index) {
    assert index <= 6 => settlementFee(id, breakpointTime(index)) == marketSettlementFee(id, index);
}

/// For any time-to-maturity the settlement fee is enclosed between the two adjacent breakpoint values (never overshoots or undershoots).
rule settlementFeeIsBoundedByBreakpointFees(bytes32 id, uint256 timeToMaturity) {
    uint256 settlementFeeLo = marketSettlementFee(id, lowerIndex(timeToMaturity));
    uint256 settlementFeeHi = marketSettlementFee(id, upperIndex(timeToMaturity));
    uint256 fee = settlementFee(id, timeToMaturity);

    assert (settlementFeeLo <= settlementFeeHi) => (fee >= settlementFeeLo && fee <= settlementFeeHi);
    assert (settlementFeeHi <= settlementFeeLo) => (fee >= settlementFeeHi && fee <= settlementFeeLo);
}
