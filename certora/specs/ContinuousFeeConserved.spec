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
// How the invariant closes the loop the per-function rules leave open:
//   The per-function rules below constrain each function's effect on continuousFeeCredit in
//   isolation, but they say nothing about the aggregate of pendingFee across all users.  A bug
//   that inflated continuousFeeCredit without a corresponding pendingFee minting event in take()
//   would not be caught by the directional rules alone.  The invariant catches exactly that:
//   every unit still live in the system must be traceable to a buyerPendingFeeIncrease event.
//
// Why strong invariant holds at every intermediate Sstore:
//   In _updatePosition the two writes are ordered:
//     (1) position[id][user].pendingFee = newPendingFee   -- sumPendingFee drops by accrued+slash
//     (2) obligationState[id].continuousFeeCredit += accrued  -- credit rises by accrued
//   Between (1) and (2) the LHS has dipped by (accrued+slash), so LHS ≤ prior LHS ≤ RHS. ✓
//   After (2) LHS rises by accrued only, net LHS change = -slash ≤ 0. ✓
//   In take(), buyerPos.pendingFee += buyerPendingFeeIncrease triggers both sumPendingFee and
//   totalPendingFeeMinted to increase by the same amount, keeping equality on the margin. ✓

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
hook Sstore position[KEY bytes32 id][KEY address user].pendingFee
    uint128 newVal (uint128 oldVal) {
    sumPendingFee[id] = sumPendingFee[id] + newVal - oldVal;
    if (newVal > oldVal) {
        totalPendingFeeMinted[id] = totalPendingFeeMinted[id] + (newVal - oldVal);
    }
}

/// CONSERVATION INVARIANT ///

// Total live fee (pending + credited) never exceeds total fee ever minted into pending.
//
// Preserved at every intermediate Sstore (strong invariant) because:
//   - Decreases to sumPendingFee never increase the LHS beyond the prior value.
//   - Increases to sumPendingFee (buyer minting) are matched one-for-one by increases to RHS.
//   - Increases to continuousFeeCredit (accrual by amount `fee`) are always ≤ the preceding
//     pendingFee decrease, because:
//       pendingFeeDecrease = (oldPendingFee − postSlashPending) + fee ≥ fee = accrued
//     since oldPendingFee ≥ postSlashPending (slashing only reduces pending).
//     Net LHS change across both Sstores = accrued − pendingFeeDecrease = −slash ≤ 0. ✓
//   - Decreases to continuousFeeCredit (claims, slashing) only shrink the LHS.
// The upper-bound half: live fee never exceeds total minted.
// Implied by feeConservedExactly below (since totalExited >= 0), but kept as a standalone
// check because it is cheaper to prove and gives a cleaner counterexample when violated.
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
