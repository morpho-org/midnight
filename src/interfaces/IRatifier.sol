// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer} from "./IMidnight.sol";

interface IRatifier {
    function isRatified(Offer memory offer, bytes memory ratifierData) external view returns (bytes32);
}
