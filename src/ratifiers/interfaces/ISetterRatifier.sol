// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";
import {Offer} from "../../interfaces/IMidnight.sol";

interface ISetterRatifier is IRatifier {
    /// ERRORS ///
    error InvalidProof();
    error Unauthorized();
    error NotRatified();

    /// EVENTS ///
    event SetIsRootRatified(
        address indexed caller, address indexed maker, bytes32 indexed root, bool newIsRootRatified
    );

    /// FUNCTIONS ///
    function setIsRootRatified(Offer memory offer, bytes32 root, bool newIsRootRatified) external;

    /// STORAGE GETTERS ///
    function isRootRatified(address maker, bytes32 root) external view returns (bool);
}
