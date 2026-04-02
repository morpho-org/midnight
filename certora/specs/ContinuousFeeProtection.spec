// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function tradingFee(bytes32 id, uint256 timeToMaturity) internal returns (uint256) => NONDET;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lossIndex(bytes32 id) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function updatePositionView(Midnight.Obligation memory obligation, bytes32 id, address user) external returns (uint128, uint128, uint128);

    function _.price() external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
}

// IdLib summary: remember the last id returned by toId.
persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

// Exact mulDivDown: floor(a * b / d)
function CVL_mulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0, "see NoDivisionByZero.spec";
    return require_uint256((to_mathint(a) * to_mathint(b)) / to_mathint(d));
}

// Exact mulDivUp: ceil(a * b / d)
function CVL_mulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0, "see NoDivisionByZero.spec";
    return require_uint256((to_mathint(a) * to_mathint(b) + to_mathint(d) - 1) / to_mathint(d));
}

function passiveFeeRecipient() returns address {
    return 0x7e3dce7c19791d65d67ef7ce3c42d2b7fe6fecb1;
}

definition WAD() returns uint256 = 10 ^ 18;

// The continuous fee is never overcharged: when a lender's credit increases via a buy-offer
// take, their pendingFee increases by at most floor(creditIncrease * continuousFee * timeToMaturity / WAD).
// This is a rounding-favors-maker guarantee: mulDivDown means the lender pays the floor, never the ceiling.
// Pending accrual is not required: time-based fee drainage inside _updatePosition only
// reduces pendingFeeDelta, never raises it. Pending slash and lossIndex saturation must still
// be excluded because they wipe credit without proportionally reducing pendingFee, breaking the inequality.
rule continuousFeeNotOvercharged(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address lender) {
    require offer.buy;

    // PASSIVE_FEE_RECIPIENT receives extra credit from every _updatePosition call on other
    // positions (line 682 of Midnight.sol), so their credit change is not governed solely
    // by the continuousFee formula.
    require lender != passiveFeeRecipient();

    bytes32 id;
    uint256 creditBefore = creditOf(id, lender);
    uint256 pendingFeeBefore = pendingFee(id, lender);
    require pendingFeeBefore <= creditBefore;
    require userLossIndex(id, lender) == lossIndex(id); // no pending slash: slashing reduces creditDelta without proportionally reducing pendingFeeDelta, which can push pendingFeeDelta above the formula
    require lossIndex(id) < max_uint128; // excludes lossIndex saturation: same risk as pending slash — credit is wiped unconditionally, shrinking creditDelta without a matching reduction in pendingFeeDelta

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId;

    // Read contFee AFTER take so it matches the value actually used by take: touchObligation
    // initializes continuousFee = defaultContinuousFee[loanToken] on the first touch, so a
    // pre-take read would see stale storage if the obligation was just created during this call.
    uint256 contFee = continuousFee(id);
    uint256 timeToMaturity = e.block.timestamp <= offer.obligation.maturity ? assert_uint256(offer.obligation.maturity - e.block.timestamp) : 0;

    // Economic viability constraint: the total continuous fee cannot exceed 100% of credit
    // (contFee * timeToMaturity / WAD <= 1). Without this, accrual inside _updatePosition
    // inflates buyerCreditIncrease above creditDelta, pushing pendingFeeDelta above the formula.
    // In practice MAX_CONTINUOUS_FEE = 317097919 (~1% APR) with realistic maturities keeps r << 1.
    require to_mathint(contFee) * to_mathint(timeToMaturity) <= WAD();

    uint256 creditAfter = creditOf(id, lender);
    uint256 pendingFeeAfter = pendingFee(id, lender);

    mathint creditDelta = to_mathint(creditAfter) - to_mathint(creditBefore);
    mathint pendingFeeDelta = to_mathint(pendingFeeAfter) - to_mathint(pendingFeeBefore);

    require creditDelta >= 0; // scope to buyers gaining credit
    assert pendingFeeDelta <= (creditDelta * to_mathint(contFee) * to_mathint(timeToMaturity)) / WAD();
}

// When a seller's credit decreases via a take, their pendingFee decreases by
// exactly ceil(postUpdatePendingFee * creditDecrease / postUpdateCredit).
// updatePositionView accounts for slash and accrual before the proportional formula runs.
rule sellerPendingFeeDecreasesProportionally(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address seller) {
    require !offer.buy;
    require seller != passiveFeeRecipient();

    bytes32 id;
    uint128 postUpdateCredit;
    uint128 postUpdatePendingFee;
    uint128 accruedFee;
    postUpdateCredit, postUpdatePendingFee, accruedFee = updatePositionView(e, offer.obligation, id, seller);

    // The Solidity mulDivUp is skipped when sellerPos.credit == 0 after _updatePosition,
    // leaving pendingFee unchanged. Require credit > 0 to stay in the proportional branch.
    require postUpdateCredit > 0;

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId;

    uint256 creditAfter = creditOf(id, seller);
    uint256 pendingFeeAfter = pendingFee(id, seller);

    mathint creditDelta = to_mathint(creditAfter) - to_mathint(postUpdateCredit);
    mathint pendingFeeDelta = to_mathint(pendingFeeAfter) - to_mathint(postUpdatePendingFee);

    require creditDelta <= 0; // scope to sellers losing credit
    mathint creditDecrease = -creditDelta;
    assert pendingFeeDelta == -((to_mathint(postUpdatePendingFee) * creditDecrease + to_mathint(postUpdateCredit) - 1) / to_mathint(postUpdateCredit));
}

// take() must not modify credit or pendingFee of any address other than the buyer, seller,
// and PASSIVE_FEE_RECIPIENT. This catches accidental writes to wrong positions (e.g. wrong id,
// wrong user) and callback side-effects.
rule takeDoesNotAffectThirdParties(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    require user != buyer;
    require user != seller;
    require user != passiveFeeRecipient();

    bytes32 id;
    uint256 creditBefore = creditOf(id, user);
    uint256 pendingFeeBefore = pendingFee(id, user);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    require id == lastId;

    assert creditOf(id, user) == creditBefore;
    assert pendingFee(id, user) == pendingFeeBefore;
}
