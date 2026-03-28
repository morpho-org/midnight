// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function UtilsLib.setBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summarySetBit(bitmap, bit);
    function UtilsLib.clearBit(uint128 bitmap, uint256 bit) internal returns (uint128) => summaryClearBit(bitmap, bit);
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => summaryMsb(bitmap);
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
