// SPDX-License-Identifier: GPL-2.0-or-later

// Continuous Fee Conservation
//
// The central property: the total fee still live in the system — pending (minted but not yet
// accrued) plus credited (accrued but not yet claimed) — can never exceed the total fee that
// was ever legitimately minted.
//
//   totalPendingFeeMinted[id]
//       = Σ buyerPendingFeeIncrease over every take() that increased a buyer's credit
//       = the only source of new continuous fee in the protocol
//
//   sumPendingFee[id] + continuousFeeCredit[id]  ≤  totalPendingFeeMinted[id]
//
// The gap is fee that has been legitimately removed from the system:
//   - accrued from pendingFee into continuousFeeCredit then claimed (buckets 1→2→3)
//   - accrued then slashed by bad debt (buckets 1→2→4)
//   - cancelled when a seller exits credit in take()
//   - cancelled when credit is withdrawn in withdraw()
//   - lost to lazy-slash realisation when _updatePosition is called after a lossIndex increase
//

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function lossIndex(bytes32 id) external returns (uint128) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function _.price() external => NONDET;

    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
}

/// GHOSTS AND HOOKS ///

// Running sum of position[id][user].pendingFee over every user for a given obligation id.
ghost mapping(bytes32 => mathint) sumPendingFee {
    init_state axiom (forall bytes32 id. sumPendingFee[id] == 0);
}

// Cumulative total of every increase to position[id][user].pendingFee.
// Increases only in take() via buyerPendingFeeIncrease — the sole source of new continuous fee.
ghost mapping(bytes32 => mathint) totalPendingFeeMinted {
    init_state axiom (forall bytes32 id. totalPendingFeeMinted[id] == 0);
}

// Hook on position[id][user].pendingFee: maintains sumPendingFee and totalPendingFeeMinted.
hook Sstore position[KEY bytes32 id][KEY address user].pendingFee uint128 newVal (uint128 oldVal) {
    sumPendingFee[id] = sumPendingFee[id] + newVal - oldVal;
    if (newVal > oldVal) {
        totalPendingFeeMinted[id] = totalPendingFeeMinted[id] + (newVal - oldVal);
    }
}

/// CONSERVATION INVARIANT ///

// Total live fee (pending + credited) never exceeds total fee ever minted into pending.
strong invariant feeInSystemBoundedByMinted(bytes32 id)
    sumPendingFee[id] + to_mathint(continuousFeeCredit(id)) <= totalPendingFeeMinted[id]
    {
        preserved with (env e) {
            require e.msg.sender != currentContract;
        }
    }

/// PER-FUNCTION SUPPORTING RULES ///

rule updatePositionAccruesFeeCredit(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = toId(e, obligation);

    uint128 accrued;
    _, _, accrued = updatePositionView(e, obligation, id, user);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    updatePosition(e, obligation, user);

    assert continuousFeeCredit(id) == feeCreditBefore + accrued;
}

rule updatePositionSetsPendingFee(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = toId(e, obligation);

    uint128 newPending;
    _, newPending, _ = updatePositionView(e, obligation, id, user);

    updatePosition(e, obligation, user);

    assert pendingFee(id, user) == newPending;
}

/// BUCKET 1 → BUCKET 2 : withdraw ///

rule withdrawAccruesFeeCredit(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, address receiver) {
    bytes32 id = toId(e, obligation);

    uint128 accrued;
    _, _, accrued = updatePositionView(e, obligation, id, onBehalf);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    withdraw(e, obligation, units, onBehalf, receiver);

    assert continuousFeeCredit(id) == feeCreditBefore + accrued;
}

/// BUCKET 1 (mint) + BUCKET 1 → BUCKET 2 (accrual) : take ///

rule takeOnlyIncreasesFeeCredit(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    bytes32 id = toId(e, offer.obligation);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert continuousFeeCredit(id) >= feeCreditBefore;
}

rule takeMintsPendingFeeForBuyer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    bytes32 id = toId(e, offer.obligation);
    address buyer = offer.buy ? offer.maker : taker;

    uint128 newPendingBefore;
    _, newPendingBefore, _ = updatePositionView(e, offer.obligation, id, buyer);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert pendingFee(id, buyer) >= newPendingBefore;
}

/// BUCKET 2 → BUCKET 3 : claimContinuousFee ///

rule claimReducesFeeCredit(env e, Midnight.Obligation obligation, uint256 amount, address receiver) {
    bytes32 id = toId(e, obligation);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    claimContinuousFee(e, obligation, amount, receiver);

    assert continuousFeeCredit(id) == feeCreditBefore - amount;
}

/// BUCKET 2 → BUCKET 4 : liquidate bad debt ///

rule liquidateDoesNotIncreaseFeeCredit(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(e, obligation);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert continuousFeeCredit(id) <= feeCreditBefore;
}

// Uses totalUnits as the proxy for "no bad debt" rather than lossIndex: when lossIndex is
// already saturated at type(uint128).max it stays at max even as bad debt is realized, yet
// continuousFeeCredit is still zeroed.  totalUnits always decreases by badDebt regardless.
rule liquidateWithoutBadDebtPreservesFeeCredit(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(e, obligation);
    uint256 totalUnitsBefore = totalUnits(id);
    uint256 feeCreditBefore = continuousFeeCredit(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert totalUnits(id) == totalUnitsBefore => continuousFeeCredit(id) == feeCreditBefore;
}

/// GLOBAL CONSERVATION : no other function touches continuousFeeCredit ///

// continuousFeeCredit can only be modified by the five functions with explicit per-function rules.
// Together with those rules this closes the continuousFeeCredit side of the bypass argument.
rule onlyExpectedFunctionsChangeFeeCredit(method f, env e, calldataarg args, bytes32 id)
filtered {
    f -> !f.isView
        && f.selector != sig:updatePosition(Midnight.Obligation, address).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector
        && f.selector != sig:claimContinuousFee(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
} {
    uint256 feeCreditBefore = continuousFeeCredit(id);
    f(e, args);
    assert continuousFeeCredit(id) == feeCreditBefore;
}

/// GLOBAL CONSERVATION : no other function touches pendingFee ///

rule onlyExpectedFunctionsChangePendingFee(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector
        && f.selector != sig:updatePosition(Midnight.Obligation, address).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
} {
    uint128 pendingFeeBefore = pendingFee(id, user);
    f(e, args);
    assert pendingFee(id, user) == pendingFeeBefore;
}
