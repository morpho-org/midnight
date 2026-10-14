// SPDX-License-Identifier: GPL-2.0-or-later
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

    // Callbacks can reenter and change the state arbitrarily, this adds no assumption: see FlashLiquidateCallback.sol.
    // The gaps until tokens are paid back are tracked by pendingReceipt and flashloans, see CVL_transferFrom.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onFlashLoan(address caller, address[] tokens, uint256[] amounts, bytes data) external => DISPATCHER(true);
    function _.onLiquidate(address liquidator, bytes32 id, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, bytes data, uint256 badDebt) external => DISPATCHER(true);
    function _.onRepay(bytes32 id, Midnight.Market market, uint256 units, address onBehalf, bytes data) external => DISPATCHER(true);

    // Good ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing, no blacklisting, no transfer limits.
    // Bad ERC20 tokens can do anything, including reentering Midnight and changing all balances, see CVL_transferFrom.
    function _.transfer(address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, a, v) expect(bool);
    function _.transferFrom(address src, address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, src, a, v) expect(bool);

    // Used to model arbitrary behavior of bad tokens.
    function _.havocAll() external => HAVOC_ALL;
}

/// HELPERS

/// ERC20 summaries.

// Token balances: token => user => balance.
ghost mapping(address => mapping(address => uint256)) tokenBalances;

// Tokens that behave correctly. The solvency invariant is only proven for these tokens.
// We use persistent ghost so that bad tokens cannot change which tokens are good.
persistent ghost mapping(address => bool) goodToken;

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    // Bad tokens can change the whole state arbitrarily, including all token balances, and return an arbitrary value.
    // Since tokenBalanceCorrect is a strong invariant, it is asserted before and assumed after the havoc.
    if (!goodToken[token]) {
        env eHavoc;
        address dummy;
        havocHelper.callHavoc(eHavoc, dummy);
        bool result;
        return result;
    }

    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    // Non-deterministically set success, which allows to simulate permissions.
    bool success;
    if (success) {
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);

        // Settle pending receipts only on the exact inbound transfer expected by take(), repay() and liquidate().
        if (dest == currentContract && pendingReceipt[token] == value) {
            pendingReceipt[token] = 0;
        }

        // In flashLoan(), every outbound transfer lends tokens and every inbound transfer pays them back.
        if (inFlashLoan && src == currentContract) {
            flashloans[token] = flashloans[token] + value;
        }
        if (inFlashLoan && dest == currentContract) {
            flashloans[token] = flashloans[token] - value;
        }
    }
    return success;
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

/// Callbacks summaries.

// Whether the current top-level call is flashLoan(). It is set in the preserved blocks and rules below.
// We use persistent ghost so that reentrant calls cannot change it.
persistent ghost bool inFlashLoan;

// Mapping from token to the amount lent out by flashLoan() and not yet paid back, see CVL_transferFrom.
// We use persistent ghost to ensure these values are not changed by the callback.
// This is justified as we prove the rule flashLoansPaidBack which ensures that the flashloan amount after a call is the same as before.
persistent ghost mapping(address => mathint) flashloans {
    init_state axiom (forall address token. flashloans[token] == 0);
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
    collateralMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]] = newCollateral;
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

    // The withdrawable is only incremented in repay and liquidate, before the inbound transfer of the same amount.
    if (newWithdrawable > oldWithdrawable) {
        pendingReceipt[loantoken[id]] = pendingReceipt[loantoken[id]] + newWithdrawable - oldWithdrawable;
    }
}

// Receipts pending settlement: claimableSettlementFee is incremented in take, and withdrawable is incremented in repay and liquidate, before the corresponding inbound transfer happens.
// We track the gap and clear it in CVL_transferFrom.
// We use persistent ghost so that reentrant calls cannot change it, which is justified by the invariant pendingReceiptZero.
persistent ghost mapping(address => mathint) pendingReceipt {
    init_state axiom (forall address token. pendingReceipt[token] == 0);
}

hook Sstore claimableSettlementFee[KEY address token] uint256 newVal (uint256 oldVal) {
    // Except for claimSettlementFee, the claimableSettlementFee is non-decreasing, see WithdrawableMonotonicity.spec.
    if (newVal > oldVal) {
        pendingReceipt[token] = pendingReceipt[token] + newVal - oldVal;
    }
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

// For any good token, the pending receipt after a transaction is 0: every claimableSettlementFee increment in take and every withdrawable increment in repay and liquidate is paid in by the same-function inbound transfer.
weak invariant pendingReceiptZero(address token)
    goodToken[token] => pendingReceipt[token] == 0;

// For any good token, the balance of the contract is always greater than or equal to the sum of all collateral, withdrawable, and claimable settlement fee amounts for that token minus the flash loaned amount.
// Note: this invariant is strong, so it also holds before each external call, in particular before each transfer of a bad token.
strong invariant tokenBalanceCorrect(address token)
    goodToken[token] => tokenBalances[token][currentContract] >= collateralSum(token) + withdrawableSum(token) + claimableSettlementFee(token) - flashloans[token] - pendingReceipt[token]
    {
        preserved with (env e) {
            requireInvariant pendingReceiptZero(token);
            require e.msg.sender != currentContract, "only external calls";
            inFlashLoan = false;
        }
        preserved flashLoan(address[] tokens, uint256[] assets, address callback, bytes data) with (env e) {
            requireInvariant pendingReceiptZero(token);
            require e.msg.sender != currentContract, "only external calls";
            inFlashLoan = true;
        }
        preserved take(Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiverIfTakerIsSeller, address takerCallback, bytes takerCallbackData) with (env e) {
            requireInvariant pendingReceiptZero(token);
            inFlashLoan = false;
            require e.msg.sender != currentContract, "only external calls";
            requireInvariant midnightAuthorizesNobody(e.msg.sender);
            requireInvariant midnightAuthorizesNobody(offer.ratifier);
            require offer.callback != currentContract, "midnight reverts on callbacks";
            require takerCallback != currentContract, "midnight reverts on callbacks";
        }
    }

// For any token, the flash loans before and after a call is the same.
// This rule is useful to prove that using persistent ghost for the flashloans mapping is sound.
rule flashLoansPaidBack(method f, address token) {
    env e;
    calldataarg args;
    inFlashLoan = f.selector == sig:flashLoan(address[], uint256[], address, bytes).selector;
    mathint oldFlashLoan = flashloans[token];
    f(e, args);
    assert flashloans[token] == oldFlashLoan, "flashloan repaid";
}

// For any token, the amount of flash loans after a transaction is 0.
// With tokenBalanceCorrect, this proves that for any token, the balance of the contract is always greater than or equal to the sum of all collateral and withdrawable amounts for that token.
weak invariant flashLoansZero(address token)
    flashloans[token] == 0
    {
        preserved {
            inFlashLoan = false;
        }
        preserved flashLoan(address[] tokens, uint256[] assets, address callback, bytes data) with (env e) {
            inFlashLoan = true;
        }
    }
