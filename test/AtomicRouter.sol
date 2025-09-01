// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../src/Terms.sol";

// Atomic actions, no use of flash accounting
contract AtomicRouter {
    Terms terms;

    constructor(address _terms) {
        terms = Terms(_terms);
    }

    function interactionCallback(bytes calldata data) external {
        require(terms.interactionInitiator() == address(this), "wrong initiator");
        (bool success, bytes memory returnData) = address(this).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
    }

    function supplyCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        terms.interact(abi.encodeCall(this.supplyCollateralCallback, (term, collateral, assets, onBehalf, msg.sender)));
    }

    function supplyCollateralCallback(
        Term memory term,
        address collateral,
        uint256 assets,
        address onBehalf,
        address msgSender
    ) external {
        require(msg.sender == address(this), "unauthorized");
        terms.supplyCollateral(term, collateral, assets, onBehalf);
        terms.transferImbalance(collateral, msgSender, address(this), assets);
        terms.rebalance(collateral, msgSender, address(terms), assets);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 assets, address onBehalf) external {
        terms.interact(
            abi.encodeCall(this.withdrawCollateralCallback, (term, collateral, assets, onBehalf, msg.sender))
        );
    }

    function withdrawCollateralCallback(
        Term memory term,
        address collateral,
        uint256 assets,
        address onBehalf,
        address msgSender
    ) external {
        require(msg.sender == address(this), "unauthorized");
        terms.withdrawCollateral(term, collateral, assets, onBehalf);
        terms.transferImbalance(collateral, address(this), msgSender, assets);
        terms.rebalance(collateral, address(terms), msgSender, assets);
        terms.checkHealthy(term, onBehalf);
    }

    function repayDebt(Term memory term, uint256 bonds, address onBehalf) external {
        terms.interact(abi.encodeCall(this.repayDebtCallback, (term, bonds, onBehalf, msg.sender)));
    }

    function repayDebtCallback(Term memory term, uint256 bonds, address onBehalf, address msgSender) external {
        require(msg.sender == address(this), "unauthorized");
        terms.repayDebt(term, bonds, onBehalf);
        terms.transferImbalance(term.loanToken, msgSender, address(this), bonds);
        terms.rebalance(term.loanToken, msgSender, address(terms), bonds);
    }

    function take(Term memory term, uint256 bonds, address onBehalf, Offer memory offer, Signature memory _sig)
        external
    {
        terms.interact(abi.encodeCall(this.takeCallback, (term, bonds, onBehalf, offer, _sig)));
    }

    function takeCallback(Term memory term, uint256 bonds, address onBehalf, Offer memory offer, Signature memory _sig)
        external
    {
        require(msg.sender == address(this), "unauthorized");
        terms.take(term, bonds, onBehalf, offer, _sig);

        (address buyer, address seller) = offer.buy ? (offer.offering, onBehalf) : (onBehalf, offer.offering);
        terms.rebalance(offer.loanToken, buyer, seller, bonds);
        terms.checkHealthy(term, seller);
    }

    function withdrawBond(Term memory term, uint256 bonds, uint256 shares, address onBehalf) external {
        terms.interact(abi.encodeCall(this.withdrawBondCallback, (term, bonds, shares, onBehalf, msg.sender)));
    }

    function withdrawBondCallback(Term memory term, uint256 bonds, uint256 shares, address onBehalf, address msgSender)
        external
    {
        require(msg.sender == address(this), "unauthorized");
        (bonds, shares) = terms.withdrawBond(term, bonds, shares, onBehalf);
        terms.transferImbalance(term.loanToken, address(this), msgSender, bonds);
        terms.rebalance(term.loanToken, address(terms), msgSender, bonds);
    }
}
