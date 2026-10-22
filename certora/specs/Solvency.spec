// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

using Utils as Utils;
using Havoc as havocHelper;

methods {
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function claimableSettlementFee(address token) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize mulDivUp and mulDivDown by ghost functions. This is for performance of the prover.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the market id.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => CVL_toId(market);

    // Summaries for complex internals irrelevant to token balance tracking.
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;

    // Good ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing.
    // Bad ERC20 tokens can do anything, including reentering Midnight and changing all balances, see CVL_transferFrom.
    function _.transfer(address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, a, v) expect(bool);
    function _.transferFrom(address src, address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, src, a, v) expect(bool);
}

/// HELPERS

/// ERC20 summaries.

// Token balances: token => user => balance.
ghost mapping(address => mapping(address => uint256)) tokenBalances;

// Tokens that behave correctly. The solvency invariant is only proven for these tokens.
// We use persistent ghost and this mapping never changes.
persistent ghost mapping(address => bool) goodToken;

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    // Bad tokens can change the whole state arbitrarily, including token balances, and return an arbitrary value.
    // Since tokenBalanceCorrect is a strong invariant, it is asserted before and assumed after the havoc.
    if (!goodToken[token]) {
        env eHavoc;
        address dummy;
        havocHelper.callHavoc(eHavoc, dummy);
        bool result;
        return result;
    }

    // Non-deterministically revert, which allows to simulate permissions and insufficient balances.
    bool reverts;
    if (reverts) {
        revert();
    }

    tokenBalances[token][src] = require_uint256(tokenBalances[token][src] - value);
    tokenBalances[token][dest] = require_uint256(tokenBalances[token][dest] + value);

    // Every outbound transfer increases what Midnight is owed and every inbound transfer decreases it.
    // A transfer from Midnight to itself leaves it unchanged.
    if (src == currentContract) {
        owed[token] = owed[token] + value;
    }
    if (dest == currentContract) {
        owed[token] = owed[token] - value;
    }
    return true;
}

/// UtilsLib summaries.

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

/// IdLib summaries.

// Mapping from market id to its loan token.
// We use persistent ghost as the loan token of a market id never changes, also not when bad tokens havoc the state.
persistent ghost mapping(bytes32 => address) loantoken;

// Mapping from market id and collateral index to the corresponding collateral token.
// We use persistent ghost as the collateral tokens of a market id never change, also not when bad tokens havoc the state.
persistent ghost mapping(bytes32 => mapping(uint128 => address)) collateralToken;

ghost hash(bytes32) returns bytes32;

function CVL_toId(Midnight.Market market) returns bytes32 {
    // Deterministically derive an arbitrary market id from the full market.
    bytes32 id = hash(Utils.hashMarket(market));

    // Assume the market id already maps to this loan token.
    // We could also initialize on first use, but then token(0) handling needs extra constraints.
    require(loantoken[id] == market.loanToken), "remember the loan token of the market";
    require(forall uint128 collateralIndex. collateralIndex < market.collateralParams.length => collateralToken[id][collateralIndex] == market.collateralParams[collateralIndex].token), "remember the collateral tokens of the market";
    return id;
}

/// Tokens owed to Midnight.

// Mapping from token to the amount Midnight is owed by the current call: the increase of the obligations (collateral, withdrawable and claimable settlement fees) minus the increase of the balance of Midnight.
// It is increased by outbound transfers and obligation increases, and decreased by inbound transfers and obligation decreases, see CVL_transferFrom and the Sstore hooks below.
// This covers flash loans, and obligations that are increased before the corresponding inbound transfer in take, repay and liquidate.
// We use persistent ghost so that callbacks and bad tokens, which are modeled by havocs, cannot change it.
// This is justified by the rules owedPaidBack*, which ensure that no call increases the owed amount.
// Since it starts at zero and can only be decreased by any function, it will always be zero or negative between transactions.
persistent ghost mapping(address => mathint) owed {
    init_state axiom (forall address token. owed[token] == 0);
}

/// Define collateral sum and withdrawable sum.

definition collateralSum(address token) returns mathint = usum bytes32 id, address owner. collateralMirror[id][owner][token];

ghost mapping(bytes32 => mapping(address => mapping(address => mathint))) collateralMirror {
    init_state axiom (forall bytes32 id. forall address owner. forall address token. collateralMirror[id][owner][token] == 0);
    init_state axiom (forall address token. collateralSum(token) == 0);
}

// Safe require as markets limit the number of collateralParams.
hook Sload uint128 value position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] {
    require value == collateralMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]], "ghost mirror";
}

// Safe require as markets limit the number of collateralParams.
hook Sstore position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] uint128 newCollateral (uint128 oldCollateral) {
    address token = collateralToken[id][require_uint128(collateralIndex)];
    collateralMirror[id][owner][token] = newCollateral;
    owed[token] = owed[token] + newCollateral - oldCollateral;
}

definition withdrawableSum(address token) returns mathint = usum bytes32 id. withdrawableMirror[id][token];

ghost mapping(bytes32 => mapping(address => mathint)) withdrawableMirror {
    init_state axiom (forall bytes32 id. forall address token. withdrawableMirror[id][token] == 0);
    init_state axiom (forall address token. withdrawableSum(token) == 0);
}

hook Sload uint128 value marketState[KEY bytes32 id].withdrawable {
    require value == withdrawableMirror[id][loantoken[id]], "ghost mirror";
}

hook Sstore marketState[KEY bytes32 id].withdrawable uint128 newWithdrawable (uint128 oldWithdrawable) {
    withdrawableMirror[id][loantoken[id]] = newWithdrawable;
    owed[loantoken[id]] = owed[loantoken[id]] + newWithdrawable - oldWithdrawable;
}

hook Sstore claimableSettlementFee[KEY address token] uint256 newVal (uint256 oldVal) {
    owed[token] = owed[token] + newVal - oldVal;
}

/// PROPERTIES

// Midnight never authorizes anyone, so Midnight can be neither the taker nor the maker in take().
// This matters because a token may allow transferFrom without allowance when from == msg.sender, so Midnight must never be the payer.
strong invariant midnightAuthorizesNobody(address authorized)
    !isAuthorized(currentContract, authorized)
    {
        preserved with (env e) {
            require e.msg.sender != currentContract, "only external calls";
            requireInvariant midnightAuthorizesNobody(e.msg.sender);
        }
    }

// For any good token, the balance of the contract plus the amount it is owed by the current call is always greater than or equal to the sum of all collateral, withdrawable, and claimable settlement fee amounts for that token.
// Every step outside of havocs changes both sides by the same amount, see the definition of owed.
// Note: this invariant is strong, so it also holds before each external call, in particular before each transfer of a bad token and each callback.
// Since owed is never positive between transactions, the balance of good tokens will always cover the collateral, withdrawable, and claimable.
strong invariant tokenBalanceCorrect(address token)
    goodToken[token] => tokenBalances[token][currentContract] + owed[token] >= collateralSum(token) + withdrawableSum(token) + claimableSettlementFee(token);

// For any good token, no call increases the owed amount: every obligation increase and every outbound transfer is matched by an obligation decrease or an inbound transfer of the same call.
// The owed amount can decrease, for example when Midnight is the receiver of a withdrawal.
// The rule holds for any initial owed amount, so it also holds for calls reentering Midnight from a callback.
// With the init_state axiom of owed, this proves that the owed amount is non-positive after each transaction.
// With tokenBalanceCorrect, this proves that for any good token, after each transaction the balance of the contract is greater than or equal to the sum of all collateral, withdrawable, and claimable settlement fee amounts for that token.
rule owedPaidBack(env e, method f, calldataarg args, address token) filtered { f -> f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector && f.selector != sig:repay(Midnight.Market, uint256, address, address, bytes).selector && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    require goodToken[token], "only good tokens";
    require e.msg.sender != currentContract, "only external calls";
    mathint owedBefore = owed[token];

    f(e, args);

    assert owed[token] <= owedBefore;
}

// Same as owedPaidBack for take.
rule owedPaidBackTake(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData, address token) {
    require goodToken[token], "only good tokens";
    require e.msg.sender != currentContract, "only external calls";

    // Midnight can be neither the taker nor the maker, so it is never the payer.
    requireInvariant midnightAuthorizesNobody(e.msg.sender);
    requireInvariant midnightAuthorizesNobody(offer.ratifier);

    // Midnight reverts on callbacks, but the prover havocs calls to unresolved callbacks instead, so this has to be assumed.
    require offer.callback != currentContract, "Midnight reverts on callbacks";
    require takerCallback != currentContract, "Midnight reverts on callbacks";
    mathint owedBefore = owed[token];

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);

    assert owed[token] <= owedBefore;
}

// Same as owedPaidBack for repay.
rule owedPaidBackRepay(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data, address token) {
    require goodToken[token], "only good tokens";
    require e.msg.sender != currentContract, "only external calls";

    // Midnight reverts on callbacks, but the prover havocs calls to unresolved callbacks instead, so this has to be assumed.
    require callback != currentContract, "Midnight reverts on callbacks";
    mathint owedBefore = owed[token];

    repay(e, market, units, onBehalf, callback, data);

    assert owed[token] <= owedBefore;
}

// Same as owedPaidBack for liquidate.
rule owedPaidBackLiquidate(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, address token) {
    require goodToken[token], "only good tokens";
    require e.msg.sender != currentContract, "only external calls";

    // Midnight reverts on callbacks, but the prover havocs calls to unresolved callbacks instead, so this has to be assumed.
    require callback != currentContract, "Midnight reverts on callbacks";
    mathint owedBefore = owed[token];

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert owed[token] <= owedBefore;
}
