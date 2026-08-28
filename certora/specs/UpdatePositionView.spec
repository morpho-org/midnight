// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function lossFactor(bytes32) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// SAFE TRANSFERS ///
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// MUL/DIV — function summaries that compute the exact value in mathint.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    /// MISC INTERNALS irrelevant to credit / loss-factor tracking ///
    function IdLib.toId(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;

    /// EXTERNAL CALLBACKS — collapse path explosion for strong invariants. ///
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.isRatified(Midnight.Offer, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
}

/// MULDIV FUNCTION SUMMARIES ///
function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(a * b / d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256((a * b + (d - 1)) / d);
}

/// GHOSTS ///

persistent ghost mathint PRECISION {
    axiom PRECISION > 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) preciseCreditDivFactor {
    init_state axiom forall bytes32 id. forall address user. preciseCreditDivFactor[id][user] == 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) pendingFeeMirror {
    init_state axiom forall bytes32 id. forall address user. pendingFeeMirror[id][user] == 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) lastAccrualMirror {
    init_state axiom forall bytes32 id. forall address user. lastAccrualMirror[id][user] == 0;
}

/// HELPER FUNCTIONS ///

// Map factor to 1 - factor, for easier math.
definition mapFactor(mathint factor) returns mathint = 2 ^ 128 - 1 - factor;

definition cvlCredit(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;

definition cvlLastLossFactor(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lastLossFactor;

/// HOOKS ///

function updateCreditDivFactor(bytes32 id, address owner, uint128 newCredit, uint128 newFactor) {
    mathint ownerLossFactor = mapFactor(newFactor);
    require ownerLossFactor > 0 => PRECISION * newCredit % ownerLossFactor == 0, "PRECISION is 2^128!";
    preciseCreditDivFactor[id][owner] = ownerLossFactor == 0 ? 0 : PRECISION * newCredit / ownerLossFactor;
}

function checkCreditDivInvariant(bytes32 id, address owner) returns bool {
    uint128 credit = cvlCredit(id, owner);
    uint128 userFactor = cvlLastLossFactor(id, owner);
    mathint mappedFactor = mapFactor(userFactor);
    return mappedFactor == 0 ? preciseCreditDivFactor[id][owner] == 0 : preciseCreditDivFactor[id][owner] * mappedFactor == PRECISION * credit;
}

hook Sstore position[KEY bytes32 id][KEY address owner].credit uint128 newCredit (uint128 oldCredit) {
    updateCreditDivFactor(id, owner, newCredit, cvlLastLossFactor(id, owner));
}

hook Sstore position[KEY bytes32 id][KEY address owner].lastLossFactor uint128 newFactor (uint128 oldFactor) {
    updateCreditDivFactor(id, owner, cvlCredit(id, owner), newFactor);
}

hook Sload uint128 value position[KEY bytes32 id][KEY address owner].pendingFee {
    require pendingFeeMirror[id][owner] == value, "ghost mirror";
}

hook Sload uint128 value position[KEY bytes32 id][KEY address owner].lastAccrual {
    require lastAccrualMirror[id][owner] == value, "ghost mirror";
}

hook Sstore position[KEY bytes32 id][KEY address owner].pendingFee uint128 newPending (uint128 oldPending) {
    pendingFeeMirror[id][owner] = newPending;
}

hook Sstore position[KEY bytes32 id][KEY address owner].lastAccrual uint128 newLast (uint128 oldLast) {
    lastAccrualMirror[id][owner] = newLast;
}

/// INVARIANTS ///

strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

/// RULES ///

rule updatePositionViewReflectedByFactor(env e, Midnight.Market obligation, bytes32 id, address owner) {
    requireInvariant preciseCreditCorrect(id, owner);
    require lastLossFactor(id, owner) <= currentContract.marketState[id].lossFactor, "lastLossFactorLeqMarketLossFactor in Midnight";

    uint128 newCredit;
    uint128 newPending;
    uint128 fee;

    uint128 creditBefore = cvlCredit(id, owner);
    mathint preciseCreditBefore = preciseCreditDivFactor[id][owner] * mapFactor(lossFactor(id));
    mathint pendingBefore = pendingFeeMirror[id][owner];
    mathint lastAccrualBefore = lastAccrualMirror[id][owner];

    require e.block.timestamp >= lastAccrualBefore, "Time is increasing";

    newCredit, newPending, fee = updatePositionView(e, obligation, id, owner);

    assert fee <= pendingBefore, "Cannot take more fee than pending";
    assert (newCredit + fee) * PRECISION <= preciseCreditBefore, "newCredit (with fees) is at most precise credit after slashing";

    // The two monotonicity facts the SumOfCredits summaries assume about
    // `updatePositionView`. `newCredit <= creditBefore` holds because
    // postSlashCredit = credit * mapFactor(lossFactor) / mapFactor(lastLossFactor)
    // <= credit under `lossFactorLeqLastLossFactor`, and newCredit =
    // postSlashCredit - fee. Proving them here means the summaries no longer
    // rely on the indirect underflow-revert argument in `_updatePosition`.
    assert newCredit <= creditBefore, "slashing and fee accrual only decrease credit";
    assert newPending <= pendingBefore, "fee deduction only decreases pending";
}

rule updatePositionZero(env e, Midnight.Market obligation, bytes32 id, address owner) {
    require currentContract.position[id][owner].credit == 0, "Assume no credit";

    uint128 newCredit;
    uint128 newPending;
    uint128 fee;
    newCredit, newPending, fee = updatePositionView(e, obligation, id, owner);

    assert newCredit == 0 && newPending == 0 && fee == 0;
}
