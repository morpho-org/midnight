// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IMatching.sol";
import "./libraries/EventsLib.sol";

contract Matching is IMatching {
    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 rate,uint256 nonce)"
    );

    /// STORAGE ///

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    mapping(address => mapping(bytes => bool)) public enabled;

    /// FUNCTIONS ///

    function take(Term memory term, uint256 assets, bytes calldata data)
        external
        returns (bool buy, address counterparty, uint256 bonds)
    {
        (Offer memory offer, Signature memory sig) = abi.decode(data, (Offer, Signature));
        require(block.timestamp >= offer.offerStart, "offer not started");
        require(block.timestamp <= offer.offerExpiry, "offer expired");
        _checkCanUseOffer(offer, sig);
        _checkOffer(term, offer);
        require((consumed[offer.offering][offer.nonce] += assets) <= offer.assets, "consumed");
        return (offer.buy, offer.offering, assets * (1e18 + (term.maturity - block.timestamp) * offer.rate) / 1e18);
    }

    /// INTERNAL ///

    function _checkOffer(Term memory term, Offer memory offer) internal pure {
        require(offer.loanToken == term.loanToken, "Loan tokens do not match");
        require(offer.maturity == term.maturity, "Maturities do not match");

        Collateral[] memory subset = offer.buy ? term.collaterals : offer.collaterals;
        Collateral[] memory superset = offer.buy ? offer.collaterals : term.collaterals;

        uint256 j = 0;
        for (uint256 i = 0; i < subset.length; i++) {
            // Relies on the fact that the collaterals are sorted.
            // Note that we actually never check that.
            // If they are not, the matching could fail.
            while (superset[j].token != subset[i].token) j++;
            require(superset[j].lltv >= subset[i].lltv, "LLTVs do not match");
            require(subset[i].oracle == superset[j].oracle, "Oracles do not match");
            j++;
        }
    }

    function _checkCanUseOffer(Offer memory offer, Signature memory sig) internal view {
        if (sig.v == 0) {
            require(enabled[offer.offering][abi.encode(offer)], "offer not enabled");
        } else {
            bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
            bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
            bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
            address signatory = ecrecover(digest, sig.v, sig.r, sig.s);
            require(signatory != address(0) && offer.offering == signatory, "Invalid sig");
        }
    }

    function enableOffer(Offer memory offer) external {
        enabled[msg.sender][abi.encode(offer)] = true;
        emit EventsLib.EnableOffer(msg.sender, offer);
    }

    function disableOffer(Offer memory offer) external {
        enabled[msg.sender][abi.encode(offer)] = false;
        emit EventsLib.DisableOffer(msg.sender, offer);
    }
}
