// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import "../src/Terms.sol";
import "../src/Matching.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

abstract contract BaseTest is Test {
    Terms internal terms;
    Matching internal matching;
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
        matching = new Matching();

        offerTypehash = matching.OFFER_TYPEHASH();
        domainTypehash = matching.DOMAIN_TYPEHASH();

        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        loanToken = new ERC20("loan", "loan");
        collateralToken1 = new ERC20("collat1", "collat1");
        collateralToken2 = new ERC20("collat2", "collat2");

        oracle = new Oracle();

        vm.startPrank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        terms.setMatching(address(matching), true);
        vm.startPrank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        terms.setMatching(address(matching), true);
        vm.startPrank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
        vm.stopPrank();

        loanToken.approve(address(terms), type(uint256).max);
        collateralToken1.approve(address(terms), type(uint256).max);
        collateralToken2.approve(address(terms), type(uint256).max);
    }

    function toId(Term memory term) internal pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function sig(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(offerTypehash, offer));
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(matching)));
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

    function setupBond(Term memory term, uint256 bonds, bool asBorrower) internal {
        uint256 collateral = (bonds * 1e18 + term.collaterals[0].lltv - 1) / term.collaterals[0].lltv;
        setupBond(term, bonds, collateral, asBorrower);
    }

    function setupBond(Term memory term, uint256 bonds, uint256 collateral, bool asBorrower) internal {
        deal(address(loanToken), lender, bonds);
        deal(address(term.collaterals[0].token), address(this), collateral);

        terms.supplyCollateral(term, address(term.collaterals[0].token), collateral, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            asBorrower: asBorrower,
            offering: borrower,
            assets: bonds,
            loanToken: term.loanToken,
            collaterals: term.collaterals,
            maturity: term.maturity,
            rate: 0,
            nonce: 0
        });

        // take `bonds` because the rate is 0.
        terms.take(term, bonds, lender, address(matching), abi.encode(borrowOffer, sig(borrowOffer, borrowerSK)));
    }
}
