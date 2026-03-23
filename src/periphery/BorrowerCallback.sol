// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";

struct CollateralData {
    uint256 collateralIndex;
    uint256 amount;
}

contract BorrowerCallback {
    address public immutable midnight;

    constructor(address _midnight) {
        midnight = _midnight;
    }

    /// @dev Callback to supply collateral on behalf of borrower.
    /// @dev The callback contract should be authorized to supply collateral on behalf of the borrower.
    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external {
        require(msg.sender == midnight, "unauthorized");
        CollateralData[] memory collateralData = abi.decode(data, (CollateralData[]));
        for (uint256 i = 0; i < collateralData.length; i++) {
            Midnight(midnight)
                .supplyCollateral(obligation, collateralData[i].collateralIndex, collateralData[i].amount, seller);
        }
    }

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external {
        revert("not implemented");
    }

    function onLiquidate(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external {
        revert("not implemented");
    }
}
