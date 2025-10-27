// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

abstract contract BaseTest is Test {
    mapping(address => uint256) internal privateKey;

    MorphoV2 internal morphoV2;
    ERC20 internal loanToken;
    ERC20 internal collateralToken1;
    ERC20 internal collateralToken2;
    Oracle internal oracle;
    address internal borrower;
    address internal lender;
    address internal otherBorrower;
    address internal otherLender;
    address internal liquidator = makeAddr("liquidator");

    function setUp() public virtual {
        morphoV2 = new MorphoV2();

        morphoV2.setFeeSetter(address(this));

        uint256 _privateKey;
        (borrower, _privateKey) = makeAddrAndKey("borrower");
        privateKey[borrower] = _privateKey;
        (lender, _privateKey) = makeAddrAndKey("lender");
        privateKey[lender] = _privateKey;
        (otherBorrower, _privateKey) = makeAddrAndKey("otherBorrower");
        privateKey[otherBorrower] = _privateKey;
        (otherLender, _privateKey) = makeAddrAndKey("otherLender");
        privateKey[otherLender] = _privateKey;

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
    }

    function toId(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return keccak256(abi.encode(offers[0]));
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return keccak256(MathLib.sort(keccak256(abi.encode(offers[0])), keccak256(abi.encode(offers[1]))));
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](1);
        res[0] = keccak256(abi.encode(offers[1]));
        return res;
    }

    function sig(Offer[1] memory offers) internal view returns (Signature memory) {
        bytes32 _root = root(offers);
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", _root));
        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey[offers[0].maker], messageHash);
        return signature;
    }

    function sig(Offer[2] memory offers) internal view returns (Signature memory) {
        bytes32 _root = root(offers);
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", _root));
        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey[offers[0].maker], messageHash);
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
        Offer memory borrowOffer;
        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = obligationUnits;
        borrowOffer.start = block.timestamp;
        borrowOffer.expiry = block.timestamp;
        borrowOffer.startPrice = 1 ether;
        borrowOffer.expiryPrice = 1 ether;

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
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
        Offer memory borrowOffer;
        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = obligationUnits;
        borrowOffer.obligation = obligation;
        borrowOffer.start = block.timestamp;
        borrowOffer.expiry = block.timestamp + 200;
        borrowOffer.startPrice = 1e18;
        borrowOffer.expiryPrice = 1e18;

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            lender,
            borrowOffer,
            sig([borrowOffer]),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );
    }
}
