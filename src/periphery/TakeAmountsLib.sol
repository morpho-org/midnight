// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {UtilsLib} from "../libraries/UtilsLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    // Forward: units = shares.mulDiv(totalUnits + 1, totalShares + 1, !buyerIsLender).
    // When buyerIsLender (forward rounds up): inverse rounds down.
    // When !buyerIsLender (forward rounds down): inverse rounds up.
    function unitsToShares(uint256 targetUnits, uint256 totalUnits, uint256 totalShares, bool buyerIsLender)
        internal
        pure
        returns (uint256)
    {
        return targetUnits.mulDiv(totalShares + 1, totalUnits + 1, buyerIsLender);
    }

    // Forward: buyerAssets = units.mulDivDown(buyerPrice, WAD).
    function buyerAssetsToShares(
        uint256 targetBuyerAssets,
        uint256 totalUnits,
        uint256 totalShares,
        uint256 buyerPrice,
        bool buyerIsLender
    ) internal pure returns (uint256) {
        require(buyerPrice <= WAD, "buyerPrice");
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);
        return unitsToShares(targetUnits, totalUnits, totalShares, buyerIsLender);
    }

    // Forward: sellerAssets = units.mulDivDown(sellerPrice, WAD).
    function sellerAssetsToShares(
        uint256 targetSellerAssets,
        uint256 totalUnits,
        uint256 totalShares,
        uint256 sellerPrice,
        bool buyerIsLender
    ) internal pure returns (uint256) {
        uint256 targetUnits = targetSellerAssets.mulDivUp(WAD, sellerPrice);
        return unitsToShares(targetUnits, totalUnits, totalShares, buyerIsLender);
    }
}
