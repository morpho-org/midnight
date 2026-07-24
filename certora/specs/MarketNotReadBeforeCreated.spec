// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // The following summaries are sound since they do not read market state.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Market memory) internal returns (bytes32) => NONDET;

    // take's ratifier/gate checks (isRatified, canIncreaseCredit, canIncreaseDebt) run after touchMarket
    // has created the market, and are view (staticcall) so they cannot mutate Midnight storage. Summarizing
    // them as NONDET is sound for the read-before-create property and avoids the full-storage havoc that
    // resolving these unresolved external calls otherwise triggers, which blows up the solver on take.
    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;

    // Envfree getters used by the uncreated-market behavior rules below and their invariant hypotheses.
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function credit(bytes32, address) external returns (uint128) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function pendingFee(bytes32, address) external returns (uint128) envfree;
    function lastAccrual(bytes32, address) external returns (uint128) envfree;
}

/// GHOSTS ///

/// Whether a field of a market was read before that market was created.
persistent ghost mapping(bytes32 => bool) marketReadBeforeCreated;

/// HOOKS ///

/// A market is created iff its tickSpacing is non-zero. The hooks below flag the read itself,
/// value-independently: any load of a market field while the market is not yet created flips the
/// ghost, regardless of the value loaded.
/// tickSpacing is deliberately not hooked: the createdness check itself reads it, so hooking it
/// would flag legitimate reads.

hook Sload uint128 val marketState[KEY bytes32 id].totalUnits {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].lossFactor {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].withdrawable {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val marketState[KEY bytes32 id].continuousFeeCredit {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp0 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp1 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp2 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp3 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp4 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp5 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint16 val marketState[KEY bytes32 id].settlementFeeCbp6 {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint32 val marketState[KEY bytes32 id].continuousFee {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].credit {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].pendingFee {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastLossFactor {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].lastAccrual {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].debt {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateralBitmap {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].collateral[INDEX uint256 index] {
    if (currentContract.marketState[id].tickSpacing == 0) marketReadBeforeCreated[id] = true;
}

/// RULES ///

/// Check that no code path reads a field of a market before that market is created. Reads are
/// flagged value-independently by the hooks above. We exclude only the pure storage getters (by
/// selector), not all view functions: those getters legitimately return a market/position field
/// without requiring the market to be created (the field reads zero for an uncreated market by
/// design). Most computed views (e.g. settlementFee) stay in scope so the rule still catches a
/// computed view that reads a field before the market is created.
/// The two computed views updatePositionView and isHealthy are also excluded: they read position
/// fields before any createdness check, but their behavior on an uncreated market is proven benign
/// (rather than merely assumed) by updatePositionViewIsZeroIfMarketNotCreated and
/// marketIsHealthyIfNotCreated below, which show they return (0, 0, 0) and true respectively.
rule marketNotReadBeforeCreated(env e, method f, calldataarg args, bytes32 id)
filtered {
    f -> f.selector != sig:marketState(bytes32).selector
        && f.selector != sig:position(bytes32, address).selector
        && f.selector != sig:tickSpacing(bytes32).selector
        && f.selector != sig:totalUnits(bytes32).selector
        && f.selector != sig:lossFactor(bytes32).selector
        && f.selector != sig:withdrawable(bytes32).selector
        && f.selector != sig:continuousFee(bytes32).selector
        && f.selector != sig:continuousFeeCredit(bytes32).selector
        && f.selector != sig:settlementFeeCbps(bytes32).selector
        && f.selector != sig:credit(bytes32, address).selector
        && f.selector != sig:debt(bytes32, address).selector
        && f.selector != sig:pendingFee(bytes32, address).selector
        && f.selector != sig:lastAccrual(bytes32, address).selector
        && f.selector != sig:lastLossFactor(bytes32, address).selector
        && f.selector != sig:collateralBitmap(bytes32, address).selector
        && f.selector != sig:collateral(bytes32, address, uint256).selector
        && f.selector != sig:updatePositionView(Midnight.Market, bytes32, address).selector
        && f.selector != sig:isHealthy(Midnight.Market, bytes32, address).selector
} {
    require !marketReadBeforeCreated[id], "initialize the ghost variable";

    f(e, args);

    assert !marketReadBeforeCreated[id], "a market field was read before the market was created";
}

/// HELPERS FOR THE UNCREATED-MARKET BEHAVIOR RULES ///

/// A market is created iff its tickSpacing is non-zero.
function marketIsCreated(bytes32 id) returns (bool) {
    return tickSpacing(id) > 0;
}

definition userHasNoRemainingContinuousFee(bytes32 id, address user) returns bool = pendingFee(id, user) == 0;

definition userHasNoLastAccrual(bytes32 id, address user) returns bool = lastAccrual(id, user) == 0;

/// INVARIANT HYPOTHESES ///

/// These "empty if not created" invariants are proven in NotCreatedMarket.conf. Here they are only
/// requireInvariant'd (assumed) as hypotheses of the two rules below, so that the fields those views
/// read are known to be zero on an uncreated market. We deliberately do NOT import NotCreatedMarket.spec,
/// which summarizes isHealthy as NONDET; that summary would make marketIsHealthyIfNotCreated vacuous
/// since it calls isHealthy directly. Only the invariants actually needed as hypotheses are redeclared.

// Fields read by updatePositionView on an uncreated market.
strong invariant marketCreditIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => credit(id, user) == 0;

strong invariant positionLastLossFactorIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => currentContract.position[id][user].lastLossFactor == 0;

strong invariant marketLossFactorIsEmptyIfNotCreated(bytes32 id)
    !marketIsCreated(id) => currentContract.marketState[id].lossFactor == 0;

strong invariant marketPendingFeeIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => userHasNoRemainingContinuousFee(id, user);

strong invariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => userHasNoLastAccrual(id, user);

// Field read by isHealthy on an uncreated market.
strong invariant marketDebtIsEmptyIfNotCreated(bytes32 id, address user)
    !marketIsCreated(id) => debt(id, user) == 0;

/// UNCREATED-MARKET BEHAVIOR RULES ///

/// updatePositionView returns (0, 0, 0) when the market is not created. Its returns are derived
/// solely from the position's credit, lastLossFactor, pendingFee, lastAccrual and the market's
/// lossFactor, all of which are zero for an uncreated market; the Market struct argument only feeds
/// the fee computation, which collapses to 0 once pendingFee is 0. Hence excluding it from the read
/// rule above is safe.
rule updatePositionViewIsZeroIfMarketNotCreated(env e, Midnight.Market market, bytes32 id, address user) {
    require currentContract.marketState[id].tickSpacing == 0; // the market is not created

    requireInvariant marketCreditIsEmptyIfNotCreated(id, user);
    requireInvariant positionLastLossFactorIsEmptyIfNotCreated(id, user);
    requireInvariant marketLossFactorIsEmptyIfNotCreated(id);
    requireInvariant marketPendingFeeIsEmptyIfNotCreated(id, user);
    requireInvariant marketLastContinuousFeeAccrualIsEmptyIfNotCreated(id, user);

    uint128 newCredit;
    uint128 newPendingFee;
    uint128 accruedFee;
    newCredit, newPendingFee, accruedFee = updatePositionView(e, market, id, user);

    assert newCredit == 0;
    assert newPendingFee == 0;
    assert accruedFee == 0;
}

/// isHealthy returns true when the market is not created. The borrower's debt is zero for an
/// uncreated market, so the oracle-querying branch is skipped entirely (no external price() call,
/// hence no havoc) and maxDebt (0) >= debt (0) holds. Hence excluding it from the read rule above is
/// safe.
rule marketIsHealthyIfNotCreated(env e, Midnight.Market market, bytes32 id, address borrower) {
    require currentContract.marketState[id].tickSpacing == 0; // the market is not created

    requireInvariant marketDebtIsEmptyIfNotCreated(id, borrower);

    assert isHealthy(e, market, id, borrower);
}
