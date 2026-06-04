// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IRateRatifier} from "./interfaces/IRateRatifier.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "./interfaces/IEcrecoverRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../libraries/ConstantsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed offers are
/// no longer valid.
/// @dev This ratifier abstracts the offer in the price dimension. The maker signs every offer field but replacing tick
/// with rate. At ratification time the rate is converted into a price limit using simple interest.
contract RateRatifier is IRateRatifier {
    using UtilsLib for uint256;

    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function isRatified(Offer memory offer, bytes memory ratifierData) external view returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        (Signature memory sig, uint256 rate) = abi.decode(ratifierData, (Signature, uint256));
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        if (offer.buy) {
            uint256 priceLimitDown = WAD.mulDivDown(WAD, WAD + rate * timeToMaturity);
            require(offerPrice <= priceLimitDown, WorsePrice());
        } else {
            uint256 priceLimitUp = WAD.mulDivUp(WAD, WAD + rate * timeToMaturity);
            require(offerPrice >= priceLimitUp, WorsePrice());
        }
        bytes32 structHash = HashLib.hashRateOffer(offer, rate);
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address _signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == offer.maker || IMidnight(MIDNIGHT).isAuthorized(offer.maker, _signer), Unauthorized());
        return CALLBACK_SUCCESS;
    }
}
