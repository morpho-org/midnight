// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that an RCF-limited liquidation (actualRepaid == maxRepaid) makes the
// position healthy. Uses exact mulDiv implementations (floor/ceiling arithmetic)
// because the proof requires lower bounds on mulDivUp — specifically that
// mulDivUp(a, WAD, denom) * denom >= a * WAD — which the relational axioms in
// Healthiness.spec do not provide.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => CVL_price(calledContract) expect(uint256);

    // toId is summarized to a ghost-bound id (`globalId`) when the input matches
    // the global obligation ghosts, else to a distinct id. Mirrors Healthiness.spec.
    // Eliminates symbolic-keccak reasoning; storage keys become a free ghost
    // scalar rather than a hash over the symbolic struct.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation, chainId, midnight);
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => CVL_toId(obligation);

    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);

    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;

    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
    function debtOf(bytes32, address) external returns (uint256) envfree;
    function collateralBitmap(bytes32, address) external returns (uint128) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
}

// Ghost-bound id used by summaryToId. Free at rule entry; the summary pins
// matching-obligation calls to it and non-matching calls away from it.
persistent ghost bytes32 globalId;

function summaryToId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    if (equalsGlobalObligation(obligation) && midnight == currentContract) {
        require id == globalId, "toId() is deterministic";
    } else {
        require id != globalId, "toId() is injective";
    }
    return id;
}

// Legacy entry point retained for touchObligation summary.
function CVL_toId(Midnight.Obligation obligation) returns bytes32 {
    return summaryToId(obligation, 0, currentContract);
}

ghost CVL_msb(uint128) returns uint256;

persistent ghost CVL_price(address) returns uint256;

// Tight relational mulDiv axioms — uniquely pin floor/ceil values, equivalent
// to exact mathint but typically faster for the SMT.
// Axioms proven in MulDiv.spec.
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
}

function CVL_mulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0;
    return ghostMulDivDown(a, b, d);
}

function CVL_mulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    require d > 0;
    return ghostMulDivUp(a, b, d);
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost address globalObligationLoanToken;

persistent ghost uint256 globalObligationCollateralLength;

persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;

persistent ghost mapping(uint256 => address) globalObligationCollateralToken;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalObligationCollateralMaxLif;

persistent ghost uint256 globalObligationMaturity;

persistent ghost uint256 globalObligationRcfThreshold;

persistent ghost address globalObligationEnterGate;

persistent ghost address globalObligationLiquidatorGate;

definition collateralMatches(Midnight.Obligation obligation, uint256 index) returns bool =
    (index < globalObligationCollateralLength
        => obligation.collateralParams[index].oracle == globalObligationCollateralOracle[index]
        && obligation.collateralParams[index].token == globalObligationCollateralToken[index]
        && obligation.collateralParams[index].lltv == globalObligationCollateralLLTV[index]
        && obligation.collateralParams[index].maxLif == globalObligationCollateralMaxLif[index]);

function equalsGlobalObligation(Midnight.Obligation obligation) returns (bool) {
    return obligation.loanToken == globalObligationLoanToken
        && obligation.collateralParams.length == globalObligationCollateralLength
        && collateralMatches(obligation, 0)
        && collateralMatches(obligation, 1)
        && collateralMatches(obligation, 2)
        && obligation.maturity == globalObligationMaturity
        && obligation.rcfThreshold == globalObligationRcfThreshold
        && obligation.enterGate == globalObligationEnterGate
        && obligation.liquidatorGate == globalObligationLiquidatorGate;
}

function getGlobalObligation() returns (Midnight.Obligation) {
    Midnight.Obligation obligation;
    require equalsGlobalObligation(obligation), "get global obligation";
    return obligation;
}

rule concreteObligationHealthyAfterMaxRcfLiquidation(env e, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require globalObligationLoanToken == 0x0000000000000000000000000000000000001001;
    require globalObligationCollateralLength == 1;
    require globalObligationCollateralOracle[0] == 0x0000000000000000000000000000000000001003;
    require globalObligationCollateralToken[0] == 0x0000000000000000000000000000000000001002;
    require globalObligationCollateralLLTV[0] == 770000000000000000;
    require globalObligationCollateralMaxLif[0] == 1061007957559681697;
    require globalObligationMaturity == 2000000000;
    require globalObligationRcfThreshold == 0;
    require globalObligationEnterGate == 0;
    require globalObligationLiquidatorGate == 0;
    require callback == 0;

    Midnight.Obligation obligation = getGlobalObligation();

    uint256 lltv = globalObligationCollateralLLTV[0];
    uint256 maxLif = globalObligationCollateralMaxLif[0];
    require maxLif >= WAD();
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD();

    uint256 price = CVL_price(globalObligationCollateralOracle[0]);
    bytes32 id = CVL_toId(obligation);
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    // Guards against degenerate/vacuous configurations: non-empty position,
    // pre-maturity unhealthy (so lif = maxLif), valid RCF math.
    require collatBefore > 0;
    require e.block.timestamp < obligation.maturity;

    // No badDebt: debt covered by raw collateral value (pre-lif scaling).
    require debtBefore <= CVL_mulDivUp(CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    // RCF max-repayment formula.
    uint256 _maxDebt = CVL_mulDivDown(CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    require debtBefore > _maxDebt;
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - _maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    uint256 actualSeized;
    uint256 actualRepaid;
    actualSeized, actualRepaid = liquidate(e, obligation, 0, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require actualRepaid == _maxRepaid;

    // Pin post-liquidate storage so isHealthy reads consistent values.
    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);
    assert collatAfter == collatBefore - actualSeized;
    assert debtAfter == debtBefore  - actualRepaid;

    assert isHealthy(obligation, id, borrower);
}

rule symbolicObligationHealthyAfterMaxRcfLiquidation(env e, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    // Healthiness.spec-style obligation modeling: obligation is bound to global
    // ghosts via equalsGlobalObligation, ghost values themselves are free —
    // genuinely "symbolic over obligation" without exposing a free struct param
    // to via_ir's per-call-site decode. Storage keys come from globalId, not a
    // keccak of the symbolic struct.
    require globalObligationCollateralLength == 1;

    Midnight.Obligation obligation = getGlobalObligation();

    uint256 lltv = globalObligationCollateralLLTV[0];
    uint256 maxLif = globalObligationCollateralMaxLif[0];
    require maxLif >= WAD();
    uint256 lifTimesLltv = CVL_mulDivUp(maxLif, lltv, WAD());
    require lifTimesLltv < WAD();

    uint256 price = CVL_price(globalObligationCollateralOracle[0]);
    bytes32 id = CVL_toId(obligation);     // pinned to globalId by summaryToId
    uint256 collatBefore = collateral(id, borrower, 0);
    uint256 debtBefore = debtOf(id, borrower);

    // Pin liquidate's collateral-loop path to index 0. msb(bitmap) is a free
    // ghost — without this, solver explores all 128 indices.
    require collateralBitmap(id, borrower) == 1;
    require CVL_msb(1) == 0;

    require collatBefore > 0;
    require e.block.timestamp < globalObligationMaturity;

    require debtBefore <= CVL_mulDivUp(CVL_mulDivUp(collatBefore, price, ORACLE_PRICE_SCALE()), WAD(), maxLif);

    uint256 _maxDebt = CVL_mulDivDown(CVL_mulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    require debtBefore > _maxDebt;
    uint256 _maxRepaid = CVL_mulDivUp(assert_uint256(debtBefore - _maxDebt), WAD(), assert_uint256(WAD() - lifTimesLltv));

    uint256 actualSeized;
    uint256 actualRepaid;
    actualSeized, actualRepaid = liquidate(e, obligation, 0, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    require actualRepaid == _maxRepaid;

    uint256 collatAfter = collateral(id, borrower, 0);
    uint256 debtAfter = debtOf(id, borrower);
    assert collatAfter == collatBefore - actualSeized;
    assert debtAfter == debtBefore - actualRepaid;

    assert isHealthy(obligation, id, borrower);
}
