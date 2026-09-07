// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {ISetterRateRatifier} from "./interfaces/ISetterRateRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../libraries/ConstantsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev This ratifier checks that an authorized address has ratified the root of a Merkle tree of rate offers, and
/// that the offer is a leaf in that tree.
/// @dev The ratifier data must contain the root, the leaf index, the Merkle proof, and the start and expiry rates.
/// @dev The leaf index determines each sibling's left/right position during Merkle proof verification.
/// @dev The maker sets a start and expiry rate instead of a fixed price. Both are WAD-scaled per-second rates.
/// At ratification, the rate is linearly interpolated over the offer lifetime and used as a price limit against
/// the taker's set price.
/// @dev This ratifier must only be used with the Midnight instance at MIDNIGHT.
contract SetterRateRatifier is ISetterRateRatifier {
    using UtilsLib for uint256;

    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRootRatified;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
    /// tree might not be ratified or unratified by a single call to this function.
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        isRootRatified[maker][root] = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, maker, root, newIsRootRatified);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof, uint256 startRate, uint256 expiryRate) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[], uint256, uint256));

        uint256 rate = startRate;
        if (startRate != expiryRate) {
            uint256 elapsed = block.timestamp - offer.start;
            uint256 duration = offer.expiry - offer.start;
            if (startRate > expiryRate) {
                rate = startRate - (startRate - expiryRate).mulDivDown(elapsed, duration);
            } else {
                rate = startRate + (expiryRate - startRate).mulDivDown(elapsed, duration);
            }
        }

        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        if (offer.buy) {
            uint256 priceLimitDown = WAD.mulDivDown(WAD, WAD + rate * timeToMaturity);
            require(offerPrice <= priceLimitDown, WorsePrice());
        } else {
            uint256 priceLimitUp = WAD.mulDivUp(WAD, WAD + rate * timeToMaturity);
            require(offerPrice >= priceLimitUp, WorsePrice());
        }

        require(
            HashLib.isLeaf(root, HashLib.hashRateOffer(offer, startRate, expiryRate), leafIndex, proof), InvalidProof()
        );
        require(isRootRatified[offer.maker][root], NotRatified());
        return CALLBACK_SUCCESS;
    }
}
