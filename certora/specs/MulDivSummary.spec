// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function mulDivDown(uint256, uint256, uint256) external returns (uint256) envfree;
    function mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;

    // Exact floor: res = floor(x*y/d).
    require to_mathint(res) * to_mathint(d) <= to_mathint(x) * to_mathint(y);
    require (to_mathint(res) + 1) * to_mathint(d) > to_mathint(x) * to_mathint(y);
    return res;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;

    // Exact ceil: res = ceil(x*y/d).
    require to_mathint(res) * to_mathint(d) >= to_mathint(x) * to_mathint(y);
    require res == 0 || (to_mathint(res) - 1) * to_mathint(d) < to_mathint(x) * to_mathint(y);
    return res;
}

/// The summary is an over-approximation: every value the implementation can produce is also
/// a valid output of the summary. In other words, summary(x,y,d) == impl(x,y,d) whenever
/// the implementation does not revert.
rule mulDivDownSummaryIsSound(uint256 x, uint256 y, uint256 d) {
    uint256 impl = mulDivDown(x, y, d);
    uint256 summ = summaryMulDivDown(x, y, d);
    assert impl == summ;
}

rule mulDivUpSummaryIsSound(uint256 x, uint256 y, uint256 d) {
    uint256 impl = mulDivUp(x, y, d);
    uint256 summ = summaryMulDivUp(x, y, d);
    assert impl == summ;
}
