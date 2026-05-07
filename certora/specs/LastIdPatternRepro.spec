// SPDX-License-Identifier: GPL-2.0-or-later

// Minimal reproducer: under the lastId ghost-binding pattern the storage
// write→read link across liquidate is lost.
//
// Setup: toId summary returns nondet bytes32, side-effects ghost lastId.
// Rule binds `bytes32 id;` (free), reads collateral[id, borrower, 0] before
// the call, then `require id == lastId` after, then reads again. The post
// read uses the resolved id; the pre read uses a symbolic id that the SMT
// can resolve to a different position. Assertion violated.
//
// Foundry test/RcfReproTest.sol confirms storage decrement matches
// returned actualSeized at byte-identical state — so CEX is a CVL artefact.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => CVL_toId(obligation);
    function touchObligation(Midnight.Obligation memory obligation) internal returns (bytes32) => CVL_toId(obligation);

    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    function _.price() external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.canLiquidate(address) external => NONDET;


    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
}

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

// Expected CEX. Contract decrements collateral[collateralIndex] by exactly
// the returned actualSeized in the seizedAssets-input path, regardless of
// badDebt. lastId binding lets SMT decouple pre/post storage reads.
rule storageDecouples_lastId(
    env e, Midnight.Obligation obligation, uint256 seizedAssets,
    address borrower, address receiver, address callback, bytes data
) {
    require obligation.collateralParams.length == 1;

    bytes32 id;
    uint256 collatBefore = collateral(id, borrower, 0);
    require seizedAssets > 0;
    require collatBefore >= seizedAssets;

    uint256 actualSeized;
    actualSeized, _ = liquidate(e, obligation, 0, seizedAssets, 0, borrower, receiver, callback, data);

    require id == lastId;

    uint256 collatAfter = collateral(id, borrower, 0);

    assert collatAfter == collatBefore - actualSeized;
}
