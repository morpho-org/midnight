// SPDX-License-Identifier: GPL-2.0-or-later

using PendingFeeComputations as PendingFeeComputations;

methods {
    function PendingFeeComputations.subtractProportionalUp(uint256 pendingFee, uint256 credit, uint256 newCredit) external returns (uint256) envfree;
    function PendingFeeComputations.scaleDown(uint256 pendingFee, uint256 credit, uint256 newCredit) external returns (uint256) envfree;

    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
}

rule pendingFeeScaleSameAsSubtractMulDivUp(uint256 pendingFee, uint256 credit, uint256 newCredit) {
    require credit > 0, "the computation is skipped when credit is zero";
    require newCredit <= credit, "see invariant pendingFeeIsSmallerThanCredit";
    assert PendingFeeComputations.subtractProportionalUp(pendingFee, credit, newCredit) == PendingFeeComputations.scaleDown(pendingFee, credit, newCredit);
}

invariant pendingFeeIsSmallerThanCredit(bytes32 id, address user)
    pendingFee(id, user) <= creditOf(id, user);
