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

    mapping(address => mapping(bytes32 => bool)) signed;

    /// FUNCTIONS ///

    function take(Term memory term, uint256 assets, bytes calldata data)
        external
        returns (bool buy, address counterparty, uint256 bonds)
    {
        (Offer memory offer, Signature memory sig) = abi.decode(data, (Offer, Signature));
        _checkSignature(offer, sig);
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

    function _checkSignature(Offer memory offer, Signature memory signature) internal view {
        // Interpret v == 0 as a contract signature.
        if (signature.v == 0) {
            require(signed[offer.offering][keccak256(abi.encode(offer))], "Invalid contract signature");
        } else {
            bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
            bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
            bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
            address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
            require(signatory != address(0) && offer.offering == signatory, "Invalid signature");
        }
    }

    function signOffer(Offer memory offer) external {
        signed[msg.sender][keccak256(abi.encode(offer))] = true;
        emit EventsLib.SignOffer(msg.sender, offer);
    }

    function revokeOffer(Offer memory offer) external {
        signed[msg.sender][keccak256(abi.encode(offer))] = false;
        emit EventsLib.RevokeOffer(msg.sender, offer);
    }
}
