// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;

    function _.price() external => NONDET;
}

strong invariant sharePriceBelowOne(bytes32 id)
    totalShares(id) >= totalUnits(id);
