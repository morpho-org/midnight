// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Seizure, Term, Order, Offer, Signature} from "./ITerms.sol";

interface IRatifier {
    function checkRatified(Offer memory offer, bool isRatified, bytes memory data) external returns (bytes32);
}

interface IBuyer {
    function onBuy(Term memory term, uint256 assets, uint256 bonds, address buyer, bytes calldata hookData) external;
}

interface ISeller {
    function onSell(Term memory term, uint256 assets, uint256 bonds, address seller, bytes calldata hookData)
        external;
}

interface ILiquidator {
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external;
}
