// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMakerCallbackDataRatifier} from "./interfaces/IMakerCallbackDataRatifier.sol";
import {IRatifier} from "../interfaces/IRatifier.sol";
import {Offer} from "../interfaces/IMidnight.sol";

/// @dev Wraps one ratifier, replacing abi.encode(makerData, takerData) with makerData before verification.
/// @dev The maker authorizes this wrapper on Midnight. The inner ratifier's standard leaf binds the callback and
/// keccak256(makerData), but not takerData. offer.ratifier remains this wrapper, not RATIFIER: a leaf signed for the
/// inner ratifier directly cannot be used through the wrapper, nor can a wrapper leaf be used directly on Midnight.
/// @dev Signature domains and cancellation remain those of the inner ratifier. Only use inner ratifiers that support
/// forwarded calls and whose validation does not depend on msg.sender being Midnight.
contract MakerCallbackDataRatifier is IMakerCallbackDataRatifier {
    address public immutable RATIFIER;

    constructor(address ratifier) {
        RATIFIER = ratifier;
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address taker) external view returns (bytes32) {
        (bytes memory makerData,) = abi.decode(offer.callbackData, (bytes, bytes));
        // This external call's decoded memory is private to this invocation; the caller's offer is unchanged.
        offer.callbackData = makerData;
        return IRatifier(RATIFIER).isRatified(offer, ratifierData, taker);
    }
}
