// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function getBit(uint128 bitmap, uint256 bit) external returns (bool) envfree;
    function setBit(uint128 bitmap, uint256 bit) external returns (uint128) envfree;
    function clearBit(uint128 bitmap, uint256 bit) external returns (uint128) envfree;
    function msb(uint128 bitmap) external returns (uint256) envfree;
    function countBits(uint128 bitmap) external returns (uint256) envfree;
}

/// RULES ///

rule zeroBitmapEmpty(uint256 bit) {
    bool isBitSet = getBit(0, bit);
    assert !isBitSet, "zero bitmap has no bit set";
    assert countBits(0) == 0, "zero bitmap has count zero";
}

rule getBitmapOutOfRange(uint128 bitmap, uint256 bit) {
    bool isBitSet = getBit(bitmap, bit);
    assert bit >= 128 => !isBitSet, "bitmap is limited to 128 bits";
}

rule setBitSetsBit(uint128 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 128, "bitmap is limited to 128 bits";
    require otherBit < 128, "bitmap is limited to 128 bits";

    bool otherBefore = getBit(bitmap, otherBit);
    bool wasSet = getBit(bitmap, bit);
    uint256 countBefore = countBits(bitmap);

    uint128 bitmapAfter = setBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);
    uint256 countAfter = countBits(bitmapAfter);

    assert bitAfter, "setBit sets the bit";
    assert otherBit != bit => otherBefore == otherAfter, "setBit doesn't change other bits";
    assert countAfter == countBefore + (wasSet ? 0 : 1), "setBit increments count when bit was clear";
}

rule clearBitClearsBit(uint128 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 128, "bitmap is limited to 128 bits";
    require otherBit < 128, "bitmap is limited to 128 bits";

    bool otherBefore = getBit(bitmap, otherBit);
    bool wasSet = getBit(bitmap, bit);
    uint256 countBefore = countBits(bitmap);

    uint128 bitmapAfter = clearBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);
    uint256 countAfter = countBits(bitmapAfter);

    assert !bitAfter, "clearBit clears the bit";
    assert otherBit != bit => otherBefore == otherAfter, "clearBit doesn't change other bits";
    assert countAfter == countBefore - (wasSet ? 1 : 0), "clearBit decrements count when bit was set";
}

rule countBitsAtMost128(uint128 bitmap) {
    uint256 count = countBits(bitmap);
    assert count <= 128;
}

rule countBitsPositiveWhenBitSet(uint128 bitmap, uint256 bit) {
    require getBit(bitmap, bit), "bit is set";
    uint256 count = countBits(bitmap);
    assert count > 0;
}

rule msbReturnsLargestSetBit(uint128 bitmap) {
    uint256 msbBit = msb(bitmap);
    uint256 otherBit;

    assert bitmap == 0 => msbBit == 2 ^ 256 - 1;
    assert bitmap != 0 => msbBit < 128;
    assert bitmap != 0 => getBit(bitmap, msbBit);
    assert bitmap != 0 && getBit(bitmap, otherBit) => otherBit <= msbBit;
}
