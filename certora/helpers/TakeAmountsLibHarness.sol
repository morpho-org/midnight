// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../../src/interfaces/IMidnight.sol";
import {TakeAmountsLib} from "../../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsLibHarness {
    function buyerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        external
        view
        returns (uint256)
    {
        return TakeAmountsLib.buyerAssetsToUnits(midnight, id, offer, targetBuyerAssets);
    }

    function sellerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        external
        view
        returns (uint256)
    {
        return TakeAmountsLib.sellerAssetsToUnits(midnight, id, offer, targetSellerAssets);
    }
}
