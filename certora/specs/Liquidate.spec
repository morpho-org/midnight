// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isHealthy(Midnight.Obligation obligation, bytes32 id, address borrower) external returns (bool) envfree;

    function _.price() external => CVL_price(calledContract) expect(uint256);
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);
    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);
}

/// HELPERS ///

// IdLib summary: remember the last id returned by toId.

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    // non-deterministic id
    bytes32 id;
    lastId = id;
    return id;
}

// UtilsLib summaries: msb, mulDivDown, and mulDivUp are deterministic

ghost CVL_msb(uint256) returns uint256;

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

// Oracle summary: we assume the price does not change during the execution of a transaction.

ghost CVL_price(address) returns uint256;

// RULES ///

rule liquidateRequireUnhealthy(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id;
    bool isHealthyBefore = isHealthy(obligation, id, borrower);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // it's okay to check only after the call that the prover chose the correct id.
    require id == lastId, "id should be derived from obligation";

    assert !isHealthyBefore || e.block.timestamp > obligation.maturity, "liquidate can only be called on unhealthy obligations";
}
