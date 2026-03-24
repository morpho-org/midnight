// SPDX-License-Identifier: GPL-2.0-or-later

using PendingFeeComputations as PendingFeeComputations;

methods {
    function PendingFeeComputations.subtractProportionalUp(uint256 pendingFee, uint256 credit, uint256 newCredit) external returns (uint256) envfree;
    function PendingFeeComputations.scaleDown(uint256 pendingFee, uint256 credit, uint256 newCredit) external returns (uint256) envfree;

    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
}

rule pendingFeeScaleSameAsSubtractMulDivUp(uint256 pendingFee, uint256 credit, uint256 newCredit) {
    assert PendingFeeComputations.subtractProportionalUp(pendingFee, credit, newCredit) == PendingFeeComputations.scaleDown(pendingFee, credit, newCredit);
}

rule pendingFeeScaleDoesntRevert(uint256 pendingFee, uint256 credit, uint256 newCredit) {
    require credit > 0, "the computation is skipped when credit is zero";
    require pendingFee < 2 ^ 128, "pending fee is stored on 128 bits";
    require newCredit < 2 ^ 128, "credit is stored on 128 bits";
    PendingFeeComputations.scaleDown@withrevert(pendingFee, credit, newCredit);
    assert !lastReverted;
}

rule pendingFeeSubtractProportionalUpDoesntRevert(uint256 pendingFee, uint256 credit, uint256 newCredit) {
    require credit > 0, "the computation is skipped when credit is zero";
    require pendingFee < 2 ^ 128, "pending fee is stored on 128 bits";
    require credit < 2 ^ 128, "credit is stored on 128 bits";
    require pendingFee <= credit, "see invariant pendingFeeBoundedByCredit";
    require newCredit <= credit, "subtractProportionalUp is used on decreasing credit";
    PendingFeeComputations.subtractProportionalUp@withrevert(pendingFee, credit, newCredit);
    assert !lastReverted;
}
