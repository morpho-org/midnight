// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Offer, Signature, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

abstract contract BaseTest is Test {
    using MathLib for uint256;

    mapping(address => uint256) internal privateKey;

    MorphoV2 internal morphoV2;
    ERC20 internal loanToken;
    ERC20 internal collateralToken1;
    ERC20 internal collateralToken2;
    Oracle internal oracle1;
    Oracle internal oracle2;
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

        oracle1 = new Oracle();
        oracle2 = new Oracle();

        vm.prank(lender);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(otherLender);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(otherBorrower);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(morphoV2), type(uint256).max);

        loanToken.approve(address(morphoV2), type(uint256).max);
        collateralToken1.approve(address(morphoV2), type(uint256).max);
        collateralToken2.approve(address(morphoV2), type(uint256).max);
    }

    // helpers.

    function collateralize(Obligation memory obligation, address _borrower, uint256 debt) internal {
        uint256 collateral = debt.mulDivUp(WAD, obligation.collaterals[0].lltv);
        deal(address(obligation.collaterals[0].token), address(this), collateral);
        collateralToken1.approve(address(morphoV2), collateral);
        morphoV2.supplyCollateral(obligation, address(obligation.collaterals[0].token), collateral, _borrower);
    }

    // hardcodes the right root, signature, proof, and callback (no callback)
    function take(
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        Offer memory offer
    ) internal {
        morphoV2.take(
            buyerAssets,
            sellerAssets,
            obligationUnits,
            obligationShares,
            taker,
            offer,
            sig([offer]),
            root([offer]),
            proof([offer]),
            address(0),
            hex""
        );
    }

    function setupOtherUsers(Obligation memory obligation, uint256 units) internal {
        deal(address(loanToken), otherLender, units); // assets = units because price is 1.

        Offer memory lenderOffer;
        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = otherLender;
        lenderOffer.assets = units;
        lenderOffer.group = keccak256(abi.encode("non zero group"));
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.startPrice = 1 ether;
        lenderOffer.expiryPrice = 1 ether;

        collateralize(obligation, otherBorrower, units);
        take(0, 0, units, 0, otherBorrower, lenderOffer);
    }

    function createBadDebt(Obligation memory obligation) internal {
        (address badBorrower, uint256 badBorrowerPrivateKey) = makeAddrAndKey("badBorrower");
        privateKey[badBorrower] = badBorrowerPrivateKey;
        address unluckyLender = makeAddr("unluckyLender");
        vm.prank(unluckyLender);
        loanToken.approve(address(morphoV2), type(uint256).max);

        Offer memory badBorrowerOffer;
        badBorrowerOffer.obligation = obligation;
        badBorrowerOffer.buy = false;
        badBorrowerOffer.maker = badBorrower;
        badBorrowerOffer.assets = 100;
        badBorrowerOffer.start = block.timestamp;
        badBorrowerOffer.expiry = block.timestamp + 200;
        badBorrowerOffer.startPrice = 1 ether;
        badBorrowerOffer.expiryPrice = 1 ether;

        deal(obligation.collaterals[0].token, address(this), 135);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[0].token, 135, badBorrower);

        deal(address(loanToken), unluckyLender, 100);

        take(100, 0, 0, 0, unluckyLender, badBorrowerOffer);

        Oracle(obligation.collaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        morphoV2.liquidate(obligation, new Seizure[](0), badBorrower, "");

        assertNotEq(
            morphoV2.totalUnits(toId(obligation)), morphoV2.totalShares(toId(obligation)), "total units != total shares"
        );

        // then empty the market (borrow side only).
        deal(address(loanToken), address(this), morphoV2.debtOf(badBorrower, toId(obligation)));
        morphoV2.repay(obligation, morphoV2.debtOf(badBorrower, toId(obligation)), badBorrower);
        assertEq(morphoV2.debtOf(badBorrower, toId(obligation)), 0, "debt");

        // reset the price.
        Oracle(obligation.collaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
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
        deal(address(loanToken), lender, obligationUnits);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = obligationUnits;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp;
        borrowerOffer.startPrice = 1 ether;
        borrowerOffer.expiryPrice = 1 ether;

        morphoV2.take(
            0,
            0,
            obligationUnits,
            0,
            lender,
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer]),
            address(0),
            hex""
        );
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
