// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import "../src/Terms.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

abstract contract BaseTest is Test {
    Terms internal terms;
    ERC20 internal loanToken;
    ERC20 internal collateralToken1;
    ERC20 internal collateralToken2;
    Oracle internal oracle;
    uint256 internal borrowerSK;
    address internal borrower;
    uint256 internal lenderSK;
    address internal lender;
    address internal liquidator = makeAddr("liquidator");
    bytes32 internal offerTypehash; // to avoid calls.
    bytes32 internal domainTypehash; // to avoid calls.

    function setUp() public virtual {
        terms = new Terms();

        offerTypehash = terms.OFFER_TYPEHASH();
        domainTypehash = terms.DOMAIN_TYPEHASH();

        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        loanToken = new ERC20("loan", "loan");
        collateralToken1 = new ERC20("collat1", "collat1");
        collateralToken2 = new ERC20("collat2", "collat2");

        oracle = new Oracle();

        vm.prank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);

        loanToken.approve(address(terms), type(uint256).max);
        collateralToken1.approve(address(terms), type(uint256).max);
        collateralToken2.approve(address(terms), type(uint256).max);
    }

    function toId(Term memory term) internal pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function sig(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(offerTypehash, offer));
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(terms)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(sk, digest);
        return signature;
    }

    function sortCollaterals(Collateral[] memory arr) internal pure returns (Collateral[] memory) {
        for (uint256 i = 1; i < arr.length; i++) {
            uint256 j = i;
            while (j > 0 && bytes20(arr[j].token) < bytes20(arr[j - 1].token)) {
                Collateral memory temp = arr[j];
                arr[j] = arr[j - 1];
                arr[j - 1] = temp;
                j--;
            }
        }
        return arr;
    }

    function setupBond(Term memory term, uint256 bonds) internal {
        uint256 collateral = (bonds * 1e18 + term.collaterals[0].lltv - 1) / term.collaterals[0].lltv;
        setupBond(term, bonds, collateral);
    }

    function setupBond(Term memory term, uint256 bonds, uint256 collateral) internal {
        deal(address(loanToken), lender, bonds);
        deal(address(term.collaterals[0].token), address(this), collateral);

        terms.supplyCollateral(term, address(term.collaterals[0].token), collateral, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: bonds,
            loanToken: term.loanToken,
            collaterals: term.collaterals,
            maturity: block.timestamp + 100,
            offerStart: block.timestamp,
            offerExpiry: block.timestamp + 200,
            rate: 0,
            nonce: 0,
            callbackAddress: address(0),
            callbackData: ""
        });

        // take `bonds` because the rate is 0.
        terms.take(term, bonds, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }

    function setupMaxBondWithCollaterals(Term memory term, uint256 collateral0, uint256 collateral1) internal {
        uint256 maxDebt = (collateral0 * term.collaterals[0].lltv + collateral1 * term.collaterals[1].lltv) / 1e18;
        setupBondWithCollaterals(term, maxDebt, collateral0, collateral1);
    }

    function setupBondWithCollaterals(Term memory term, uint256 bonds, uint256 collateral0, uint256 collateral1)
        internal
    {
        deal(address(loanToken), lender, bonds);
        deal(address(term.collaterals[0].token), address(this), collateral0);
        deal(address(term.collaterals[1].token), address(this), collateral1);

        terms.supplyCollateral(term, address(term.collaterals[0].token), collateral0, borrower);
        terms.supplyCollateral(term, address(term.collaterals[1].token), collateral1, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: bonds,
            loanToken: term.loanToken,
            collaterals: term.collaterals,
            maturity: block.timestamp + 100,
            offerStart: block.timestamp,
            offerExpiry: block.timestamp + 200,
            rate: 0,
            nonce: 0,
            callbackAddress: address(0),
            callbackData: ""
        });

        // take `bonds` because the rate is 0.
        terms.take(term, bonds, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");
    }
}
