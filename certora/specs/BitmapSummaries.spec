// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;

    function UtilsLib.setBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summarySetBit(bitmap, bit);
    function UtilsLib.clearBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summaryClearBit(bitmap, bit);
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => summaryMsb(bitmap);

    // Summarize internals irrelevant to the properties.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
}

/// SUMMARIES ///

persistent ghost summaryGetBit(uint128, uint256) returns bool {
    // see rule zeroBitmapEmpty in Bitmap.spec
    axiom forall uint256 bit. !summaryGetBit(0, bit);
}

function summarySetBit(uint128 bitmap, uint256 bit) returns (uint128) {
    uint128 result;
    assert bit < 128;
    require summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherBit. otherBit != bit && otherBit < 128 => summaryGetBit(result, otherBit) == summaryGetBit(bitmap, otherBit), "see Bitmap.spec";
    return result;
}

function summaryClearBit(uint128 bitmap, uint256 bit) returns (uint128) {
    uint128 result;
    assert bit < 128;
    require !summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherBit. otherBit != bit && otherBit < 128 => summaryGetBit(result, otherBit) == summaryGetBit(bitmap, otherBit), "see Bitmap.spec";
    return result;
}

function summaryMsb(uint128 bitmap) returns (uint256) {
    uint256 bit;
    assert bitmap != 0;

    require bit < 128, "see Bitmap.spec";
    require summaryGetBit(bitmap, bit), "see Bitmap.spec";
    require forall uint256 otherBit. summaryGetBit(bitmap, otherBit) => otherBit <= bit, "see Bitmap.spec";
    return bit;
}

strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateralOf(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].activatedCollaterals, collateralIndex));
