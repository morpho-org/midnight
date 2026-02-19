// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    // Summaries to avoid SMT solver timeout.
    function tradingFee(bytes20, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

// strong invariant sharePriceBelowOne(bytes20 id)
//     totalShares(id) >= totalUnits(id);
