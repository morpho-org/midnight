// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../interfaces/IMatching.sol";

library EventsLib {
    event SignOffer(address indexed sender, Offer offer);
    event RevokeOffer(address indexed sender, Offer offer);
}
