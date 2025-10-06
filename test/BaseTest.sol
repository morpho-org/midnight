// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import "../src/MorphoV2.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

abstract contract BaseTest is Test {
    MorphoV2 internal morphoV2;
    ERC20 internal loanToken;
    ERC20 internal collateralToken1;
    ERC20 internal collateralToken2;
    Oracle internal oracle;
    uint256 internal borrowerSK;
    address internal borrower;
    uint256 internal lenderSK;
    address internal lender;
    address internal liquidator = makeAddr("liquidator");

    function setUp() public virtual {
        morphoV2 = new MorphoV2();

        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");

        loanToken = new ERC20("loan", "loan");
        collateralToken1 = new ERC20("collat1", "collat1");
        collateralToken2 = new ERC20("collat2", "collat2");

        oracle = new Oracle();

        vm.prank(lender);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(morphoV2), type(uint256).max);

        loanToken.approve(address(morphoV2), type(uint256).max);
        collateralToken1.approve(address(morphoV2), type(uint256).max);
        collateralToken2.approve(address(morphoV2), type(uint256).max);

        vm.prank(lender);
        morphoV2.setAuthorized(address(this), true);
        vm.prank(borrower);
        morphoV2.setAuthorized(address(this), true);
    }

    function toId(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function sig(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(morphoV2)));
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

    function setupObligation(Obligation memory obligation, uint256 obligationUnits) internal {
        uint256 collateral =
            (obligationUnits * 1e18 + obligation.collaterals[0].lltv - 1) / obligation.collaterals[0].lltv;
        setupObligation(obligation, obligationUnits, collateral);
    }

    function setupObligation(Obligation memory obligation, uint256 obligationUnits, uint256 collateral) internal {
        deal(address(loanToken), lender, obligationUnits);
        deal(address(obligation.collaterals[0].token), address(this), collateral);

        morphoV2.supplyCollateral(obligation, address(obligation.collaterals[0].token), collateral, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            maker: borrower,
            assets: obligationUnits,
            loanToken: obligation.loanToken,
            collaterals: obligation.collaterals,
            maturity: block.timestamp + 100,
            start: block.timestamp,
            expiry: block.timestamp,
            startPrice: 1 ether,
            expiryPrice: 1 ether,
            nonce: 0,
            callbackAddress: address(0),
            callbackData: ""
        });

        morphoV2.take(
            obligation, 0, obligationUnits, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex""
        );
    }

    function setupMaxObligationWithCollaterals(Obligation memory obligation, uint256 collateral0, uint256 collateral1)
        internal
    {
        uint256 maxDebt =
            (collateral0 * obligation.collaterals[0].lltv + collateral1 * obligation.collaterals[1].lltv) / 1e18;
        setupObligationWithCollaterals(obligation, maxDebt, collateral0, collateral1);
    }

    function setupObligationWithCollaterals(
        Obligation memory obligation,
        uint256 obligationUnits,
        uint256 collateral0,
        uint256 collateral1
    ) internal {
        deal(address(loanToken), lender, obligationUnits);
        deal(address(obligation.collaterals[0].token), address(this), collateral0);
        deal(address(obligation.collaterals[1].token), address(this), collateral1);

        morphoV2.supplyCollateral(obligation, address(obligation.collaterals[0].token), collateral0, borrower);
        morphoV2.supplyCollateral(obligation, address(obligation.collaterals[1].token), collateral1, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            maker: borrower,
            assets: obligationUnits,
            loanToken: obligation.loanToken,
            collaterals: obligation.collaterals,
            maturity: block.timestamp + 100,
            start: block.timestamp,
            expiry: block.timestamp + 200,
            startPrice: 1e18,
            expiryPrice: 1e18,
            nonce: 0,
            callbackAddress: address(0),
            callbackData: ""
        });

        morphoV2.take(
            obligation, 0, obligationUnits, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex""
        );
    }
}
