// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";

struct CollateralData {
    uint256 collateralIndex;
    uint256 amount;
}

contract BorrowerCallback is ICallbacks {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to supply collateral on behalf of borrower.
    /// @dev The callback contract should be authorized to supply collateral on behalf of the borrower.
    function onSell(bytes32, Obligation memory obligation, address seller, uint256, uint256, uint256, bytes memory data)
        external
    {
        require(msg.sender == MIDNIGHT, "unauthorized");
        CollateralData[] memory collateralData = abi.decode(data, (CollateralData[]));
        for (uint256 i = 0; i < collateralData.length; i++) {
            Midnight(MIDNIGHT)
                .supplyCollateral(obligation, collateralData[i].collateralIndex, collateralData[i].amount, seller);
        }
    }

    function onBuy(bytes32, Obligation memory, address, uint256, uint256, uint256, bytes memory) external pure {
        revert("not implemented");
    }

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external pure {
        revert("not implemented");
    }
}
