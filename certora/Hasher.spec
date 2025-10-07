// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function usedKeccak256(bytes32, bytes32) external returns (bytes32) envfree;
    function commutativeKeccak256(bytes32, bytes32) external returns (bytes32) envfree;
}

rule functionalEquivalenceKeccak256(bytes32 x, bytes32 y) {
    assert(usedKeccak256(x, y) == commutativeKeccak256(x, y));
}

rule noRevertsUsedKeccak256(bytes32 x, bytes32 y) {
    usedKeccak256@withrevert(x, y);
    assert !lastReverted;
}

rule noRevertsCommutativeKeccak256(bytes32 x, bytes32 y) {
    commutativeKeccak256@withrevert(x, y);
    assert !lastReverted;
}
