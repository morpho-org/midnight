// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that successful calls do not underflow in any subtraction, given that every subtraction in Midnight and its
// dependencies is routed through UtilsLib.sub, and given the oracle price is bounded.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function credit(bytes32 id, address user) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;

    // Oracle integration assumption: every (collateralAmount * oraclePrice) fits in uint256.
    // Storage collateral is uint128, so boundedPrice enforces the product bound against max_uint128.
    function _.price() external => boundedPrice(calledContract) expect(uint256);

    // Deterministic toId: links call-site markets to validated state from touchMarket.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Sound return bound: tickToPrice <= WAD for non-reverting calls.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Summarize mulDivDown and mulDivUp with their proven bounds (their internal subtraction is therefore not analyzed
    // here; it is the `d - 1` in mulDivUp, which underflows only when d == 0, i.e. when the original code reverts too).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);

    // Summarize sub to track underflow.
    function UtilsLib.sub(uint256 x, uint256 y) internal returns (uint256) => subSummary(x, y);
}

/// HELPERS ///

persistent ghost bool subUnderflow;

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// Proven in CreatedMarkets.spec (createdMarketsHaveLltvLessThanOrEqualToOne)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity is bounded to uint64 as a realistic timestamp assumption for underflow analysis.
function summaryToId(Midnight.Market market) returns (bytes32) {
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "proven in CreatedMarkets.spec";
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].maxLif >= WAD() && market.collateralParams[i].maxLif <= 2 * WAD(), "proven in ExactMath.spec";
    require market.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
    return Utils.hashMarket(market);
}

// Bound every storage collateral (uint128) * oracle price product.
function boundedPrice(address oracle) returns uint256 {
    uint256 price;
    require to_mathint(price) * max_uint128 + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "same as assuming that collateral * price <= uint256 with mulDivUp rounding headroom";
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price <= WAD(), "Proven in TickToPrice.spec";
    return price;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require d > 0 => to_mathint(result) * d <= to_mathint(x) * y, "proven in MulDiv.spec (mulDivDownRoundsDown)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    require d > 0 => to_mathint(result) * d >= to_mathint(x) * y, "proven in MulDiv.spec (mulDivUpRoundsUp)";
    require d > 0 => to_mathint(result) * d <= to_mathint(x) * y + d - 1, "proven in MulDiv.spec (mulDivUpUpperBound)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    return result;
}

// Records an underflow when x < y, and returns the exact difference otherwise. On underflow the result is left
// unconstrained so that execution can continue: this maximizes the prover's freedom to reach a reverting-free
// counterexample, exactly as the multiplication summary does for overflow.
function subSummary(uint256 x, uint256 y) returns uint256 {
    uint256 result;
    if (x < y) {
        subUnderflow = true;
    } else {
        require to_mathint(result) == x - y, "exact subtraction when no underflow";
    }
    return result;
}

/// RULES ///

// Unlike multiplication overflow (which is never intended and is ruled out purely by magnitude bounds), several of
// Midnight's subtractions underflow *by design*: the underflow is the revert that rejects an out-of-range input. These
// input-guarded entry points are excluded from the parametric rule below and listed here with where their revert
// behavior is already proven:
//   - repay              : `debt -= units`                       rejects repaying more than owed       (Reverts.spec)
//   - withdraw           : `credit/withdrawable/totalUnits -= units` rejects over-withdrawal           (Reverts.spec)
//   - withdrawCollateral : `collateral -= assets`                rejects withdrawing absent collateral (Reverts.spec)
//   - claimSettlementFee : `claimableSettlementFee -= amount`    rejects over-claiming                 (Role.spec)
//   - claimContinuousFee : `continuousFeeCredit/totalUnits/withdrawable -= amount` rejects over-claiming (Role.spec)
//   - take               : `offerPrice - settlementFee`          rejects buy offers priced below the fee (Reverts.spec)
// The functions that thread through _updatePosition (take/withdraw/updatePosition) or the liquidation math (liquidate)
// have their non-reverting (hence underflow-free) behavior established under explicit preconditions by
// updatePositionDoesNotRevert and liquidateLossFactorDoesNotRevert in LossFactor.spec; updatePosition(View) is proven
// underflow-free directly below under those same preconditions.

rule noSubtractionUnderflow(method f, env e, calldataarg args)
filtered {
    f -> f.selector != sig:isHealthy(Midnight.Market, bytes32, address).selector
        && f.selector != sig:updatePositionView(Midnight.Market, bytes32, address).selector
        && f.selector != sig:updatePosition(Midnight.Market, address).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
        && f.selector != sig:claimSettlementFee(address, uint256, address).selector
        && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector
} {
    require !subUnderflow, "prestate: no underflow before call";
    f(e, args);
    assert !subUnderflow;
}

// isHealthy contains no subtraction, so this holds trivially; kept for parity with NoMultiplicationOverflow.
rule noSubtractionUnderflowIsHealthy(env e, Midnight.Market market, bytes32 id, address borrower) {
    require !subUnderflow, "prestate: no underflow before call";
    require id == summaryToId(market), "id corresponds to market";
    isHealthy(e, market, id, borrower);
    assert !subUnderflow;
}

// Preconditions are exactly those of updatePositionDoesNotRevert in LossFactor.spec.
rule noSubtractionUnderflowUpdatePositionView(env e, Midnight.Market market, bytes32 id, address user) {
    require !subUnderflow, "prestate: no underflow before call";
    require id == summaryToId(market), "id corresponds to market";
    require lastLossFactor(id, user) <= currentContract.marketState[id].lossFactor, "proven in Midnight.spec (lastLossFactorLeqMarketLossFactor)";
    require pendingFee(id, user) <= credit(id, user), "proven in Midnight.spec (pendingContinuousFeeBoundedByCredit)";
    require currentContract.position[id][user].lastAccrual <= e.block.timestamp, "lastAccrual <= block.timestamp by timestamp monotonicity";
    require e.block.timestamp < 2 ^ 128, "reasonable timestamp";
    updatePositionView(e, market, id, user);
    assert !subUnderflow;
}

// updatePosition wraps updatePositionView (same subtractions) and additionally subtracts newCredit/newPendingFee from
// the stored credit/pendingFee, both bounded by the post-slash values. Same preconditions as above.
rule noSubtractionUnderflowUpdatePosition(env e, Midnight.Market market, address user) {
    bytes32 id = summaryToId(market);
    require !subUnderflow, "prestate: no underflow before call";
    require lastLossFactor(id, user) <= currentContract.marketState[id].lossFactor, "proven in Midnight.spec (lastLossFactorLeqMarketLossFactor)";
    require pendingFee(id, user) <= credit(id, user), "proven in Midnight.spec (pendingContinuousFeeBoundedByCredit)";
    require currentContract.position[id][user].lastAccrual <= e.block.timestamp, "lastAccrual <= block.timestamp by timestamp monotonicity";
    require e.block.timestamp < 2 ^ 128, "reasonable timestamp";
    updatePosition(e, market, user);
    assert !subUnderflow;
}
