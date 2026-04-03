// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summarize internal functions that use opcodes causing HAVOC or are irrelevant to token pull provenance.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function _.price() external => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;

    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => signerSummary();
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Track which callbacks explicitly opted in by returning CALLBACK_SUCCESS.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => callbackSummary(calledContract) expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => callbackSummary(calledContract) expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    // Assume ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing, no blacklisting, no transfer limits.
    function _.transfer(address dest, uint256 value) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, dest, value) expect(bool);
    function _.transferFrom(address src, address dest, uint256 value) external with(env e) => CVL_transferFrom(e, calledContract, src, dest, value) expect(bool);
}

ghost mapping(address => mapping(address => uint256)) tokenBalances;

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

ghost mapping(address => bool) callbackReturnedSuccess {
    init_state axiom forall address a. callbackReturnedSuccess[a] == false;
}

function signerSummary() returns address {
    address result;
    signed[result] = true;
    return result;
}

function callbackSummary(address callback) returns (bytes32) {
    bytes32 result;
    callbackReturnedSuccess[callback] = result == Utils.callbackSuccess();
    return result;
}

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    bool success;
    if (success) {
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

definition buyerCallback(address offerCallback, address takerCallback, bool buy) returns address = buy ? offerCallback : takerCallback;

definition sellerCallback(address offerCallback, address takerCallback, bool buy) returns address = buy ? takerCallback : offerCallback;

definition takePayer(env e, bool buy, address maker, address buyerCb) returns address = buyerCb != 0 ? buyerCb : (buy ? maker : e.msg.sender);

rule takeCallbacksMustReturnSuccess(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    require e.msg.sender != currentContract, "only external calls";
    require taker != currentContract, "no trading with contract";
    require offer.maker != currentContract, "no trading with contract";
    require offer.callback != currentContract, "midnight reverts on callbacks";
    require takerCallback != currentContract, "midnight reverts on callbacks";

    address buyerCb = buyerCallback(offer.callback, takerCallback, offer.buy);
    address sellerCb = sellerCallback(offer.callback, takerCallback, offer.buy);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    assert buyerCb == 0 || callbackReturnedSuccess[buyerCb];
    assert sellerCb == 0 || callbackReturnedSuccess[sellerCb];
}

rule takeDebitsOnlyExplicitPayer(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address user) {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";
    require taker != currentContract, "no trading with contract";
    require offer.maker != currentContract, "no trading with contract";
    require offer.callback != currentContract, "midnight reverts on callbacks";
    require takerCallback != currentContract, "midnight reverts on callbacks";

    address buyerCb = buyerCallback(offer.callback, takerCallback, offer.buy);
    address payer = takePayer(e, offer.buy, offer.maker, buyerCb);

    uint256 balanceBefore = tokenBalances[offer.obligation.loanToken][user];

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    uint256 balanceAfter = tokenBalances[offer.obligation.loanToken][user];

    assert balanceAfter < balanceBefore => user == payer;
    assert balanceAfter < balanceBefore && buyerCb != 0 => callbackReturnedSuccess[buyerCb];
    assert balanceAfter < balanceBefore && buyerCb == 0 && offer.buy => signed[offer.maker];
}

rule repayDebitsOnlyCaller(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data, address user) {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";

    uint256 balanceBefore = tokenBalances[obligation.loanToken][user];

    repay(e, obligation, units, onBehalf, data);

    uint256 balanceAfter = tokenBalances[obligation.loanToken][user];

    assert balanceAfter < balanceBefore => user == e.msg.sender;
}

rule supplyCollateralDebitsOnlyCaller(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address user) {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";
    require collateralIndex < obligation.collaterals.length, "valid collateral index";

    address collateralToken = obligation.collaterals[collateralIndex].token;
    uint256 balanceBefore = tokenBalances[collateralToken][user];

    supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);

    uint256 balanceAfter = tokenBalances[collateralToken][user];

    assert balanceAfter < balanceBefore => user == e.msg.sender;
}

rule liquidateDebitsOnlyCaller(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, address user) {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";

    uint256 balanceBefore = tokenBalances[obligation.loanToken][user];

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    uint256 balanceAfter = tokenBalances[obligation.loanToken][user];

    assert balanceAfter < balanceBefore => user == e.msg.sender;
}

rule flashLoanDebitsOnlyCaller(env e, address token, uint256 assets, address callback, bytes data, address user) {
    require e.msg.sender != currentContract, "only external calls";
    require user != currentContract, "track external users only";
    require callback != currentContract, "midnight does not implement flashloan callbacks";

    uint256 balanceBefore = tokenBalances[token][user];

    flashLoan(e, token, assets, callback, data);

    uint256 balanceAfter = tokenBalances[token][user];

    assert balanceAfter < balanceBefore => user == e.msg.sender;
}
