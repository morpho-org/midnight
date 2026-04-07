// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {ERC20NoRevert} from "./erc20s/ERC20NoRevert.sol";
import {ERC20USDT} from "./erc20s/ERC20USDT.sol";
import {ERC20RevertToZero} from "./erc20s/ERC20RevertToZero.sol";
import {ERC20NoReturn} from "./erc20s/ERC20NoReturn.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {
    WAD,
    ORACLE_PRICE_SCALE,
    MAX_COLLATERALS,
    LIQUIDATION_CURSOR_LOW,
    LLTV_0,
    LLTV_1,
    LLTV_2,
    LLTV_3,
    LLTV_4,
    LLTV_5,
    LLTV_6,
    LLTV_7,
    LLTV_8
} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "../src/interfaces/IEcrecover.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {EcrecoverAuthorizer} from "../src/authorizers/EcrecoverAuthorizer.sol";
uint256 constant MAX_TEST_AMOUNT = type(uint128).max;

abstract contract BaseTest is Test {
    using UtilsLib for uint256;

    mapping(address => uint256) internal privateKey;

    Midnight internal midnight;
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
    EcrecoverRatifier internal ecrecoverRatifier;
    EcrecoverAuthorizer internal ecrecoverAuthorizer;

    bytes internal emptySig;

    function setUp() public virtual {
        midnight = new Midnight();
        ecrecoverRatifier = new EcrecoverRatifier(address(midnight));
        ecrecoverAuthorizer = new EcrecoverAuthorizer(address(midnight));

        midnight.setFeeSetter(address(this));

        uint256 _privateKey;
        (borrower, _privateKey) = makeAddrAndKey("borrower");
        privateKey[borrower] = _privateKey;
        (lender, _privateKey) = makeAddrAndKey("lender");
        privateKey[lender] = _privateKey;
        (otherBorrower, _privateKey) = makeAddrAndKey("otherBorrower");
        privateKey[otherBorrower] = _privateKey;
        (otherLender, _privateKey) = makeAddrAndKey("otherLender");
        privateKey[otherLender] = _privateKey;

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(ecrecoverRatifier), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(ecrecoverRatifier), true);
        vm.prank(otherBorrower);
        midnight.setIsAuthorized(otherBorrower, address(ecrecoverRatifier), true);
        vm.prank(otherLender);
        midnight.setIsAuthorized(otherLender, address(ecrecoverRatifier), true);

        uint256 tokenType = vm.envOr("TOKEN_TYPE", uint256(0));
        if (tokenType == 1) {
            loanToken = ERC20(address(new ERC20NoRevert()));
            collateralToken1 = ERC20(address(new ERC20NoRevert()));
            collateralToken2 = ERC20(address(new ERC20NoRevert()));
        } else if (tokenType == 2) {
            loanToken = ERC20(address(new ERC20USDT()));
            collateralToken1 = ERC20(address(new ERC20USDT()));
            collateralToken2 = ERC20(address(new ERC20USDT()));
        } else if (tokenType == 3) {
            loanToken = ERC20(address(new ERC20RevertToZero()));
            collateralToken1 = ERC20(address(new ERC20RevertToZero()));
            collateralToken2 = ERC20(address(new ERC20RevertToZero()));
        } else if (tokenType == 4) {
            loanToken = ERC20(address(new ERC20NoReturn()));
            collateralToken1 = ERC20(address(new ERC20NoReturn()));
            collateralToken2 = ERC20(address(new ERC20NoReturn()));
        } else {
            loanToken = new ERC20("loan", "loan");
            collateralToken1 = new ERC20("collat1", "collat1");
            collateralToken2 = new ERC20("collat2", "collat2");
        }

        oracle1 = new Oracle();
        oracle2 = new Oracle();

        vm.prank(lender);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.prank(otherLender);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.prank(otherBorrower);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(midnight), type(uint256).max);

        loanToken.approve(address(midnight), type(uint256).max);
        collateralToken1.approve(address(midnight), type(uint256).max);
        collateralToken2.approve(address(midnight), type(uint256).max);
    }

    // helpers.

    function collateralize(Obligation memory obligation, address _borrower, uint256 debt) internal {
        uint256 oraclePrice = Oracle(obligation.collateralParams[0].oracle).price();
        uint256 collateral =
            debt.mulDivUp(WAD, obligation.collateralParams[0].lltv).mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
        deal(address(obligation.collateralParams[0].token), _borrower, collateral);

        vm.startPrank(_borrower);
        ERC20(obligation.collateralParams[0].token).approve(address(midnight), 0);
        ERC20(obligation.collateralParams[0].token).approve(address(midnight), collateral);
        midnight.supplyCollateral(obligation, 0, collateral, _borrower);
        vm.stopPrank();
    }

    // hardcodes the right root, signature, proof, and callback (no callback)
    function take(uint256 units, address taker, Offer memory offer) internal returns (uint256, uint256, uint256) {
        // receiverIfTakerIsSeller param is for taker (when offer.buy == true)
        // offer.receiverIfMakerIsSeller is for maker (when offer.buy == false)
        vm.prank(taker);
        return midnight.take(units, taker, address(0), hex"", taker, offer, sig([offer]), root([offer]), proof([offer]));
    }

    function setupOtherUsers(Obligation memory obligation, uint256 units) internal {
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        deal(address(loanToken), otherLender, assets);

        Offer memory lenderOffer;
        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = otherLender;
        lenderOffer.maxUnits = units;
        lenderOffer.group = keccak256(abi.encode("non zero group"));
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        collateralize(obligation, otherBorrower, units);
        take(units, otherBorrower, lenderOffer);
    }

    function createBadDebt(Obligation memory obligation) internal {
        (address badBorrower, uint256 badBorrowerPrivateKey) = makeAddrAndKey("badBorrower");
        privateKey[badBorrower] = badBorrowerPrivateKey;
        address unluckyLender = makeAddr("unluckyLender");
        vm.prank(unluckyLender);
        loanToken.approve(address(midnight), type(uint256).max);
        Offer memory badBorrowerOffer;
        badBorrowerOffer.obligation = obligation;
        badBorrowerOffer.buy = false;
        badBorrowerOffer.maker = badBorrower;
        badBorrowerOffer.receiverIfMakerIsSeller = badBorrower;
        badBorrowerOffer.maxUnits = 100;
        badBorrowerOffer.ratifier = address(ecrecoverRatifier);
        badBorrowerOffer.start = block.timestamp;
        badBorrowerOffer.expiry = block.timestamp + 200;
        badBorrowerOffer.tick = MAX_TICK;

        vm.prank(badBorrower);

        midnight.setIsAuthorized(badBorrower, address(ecrecoverRatifier), true);
        vm.prank(badBorrower);
        midnight.setIsAuthorized(badBorrower, address(this), true);

        deal(obligation.collateralParams[0].token, address(this), 135);
        midnight.supplyCollateral(obligation, 0, 135, badBorrower);

        vm.prank(badBorrower);
        midnight.setIsAuthorized(badBorrower, address(this), false);

        deal(address(loanToken), unluckyLender, 100);

        take(100, unluckyLender, badBorrowerOffer);

        Oracle(obligation.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(obligation, 0, 0, 0, badBorrower, "");

        // then empty the market (borrow side only).
        vm.prank(badBorrower);
        midnight.setIsAuthorized(badBorrower, address(this), true);
        deal(address(loanToken), address(this), midnight.debtOf(toId(obligation), badBorrower));
        midnight.repay(obligation, midnight.debtOf(toId(obligation), badBorrower), badBorrower, hex"");
        assertEq(midnight.debtOf(toId(obligation), badBorrower), 0, "debt");

        // reset the price.
        Oracle(obligation.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE);
    }

    function toId(Obligation memory obligation) internal view returns (bytes32) {
        return IdLib.toId(obligation, block.chainid, address(midnight));
    }

    function sig(Offer[1] memory offers, address _signer) internal view returns (bytes memory) {
        return abi.encode(signature(root(offers), privateKey[_signer], offers[0].ratifier));
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _path = new bytes32[](1);
        _path[0] = keccak256(abi.encode(offers[1]));
        return _path;
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(abi.encode(offer));
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return keccak256(abi.encode(offers[0]));
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return UtilsLib.commutativeHash(keccak256(abi.encode(offers[0])), keccak256(abi.encode(offers[1])));
    }

    function domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, verifyingContract));
    }

    function signature(bytes32 _root, uint256 _privateKey, address verifyingContract)
        internal
        view
        returns (Signature memory)
    {
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, _root));
        bytes32 messageHash = keccak256(bytes.concat("\x19\x01", domainSeparator(verifyingContract), structHash));
        Signature memory _signature;
        (_signature.v, _signature.r, _signature.s) = vm.sign(_privateKey, messageHash);
        return _signature;
    }

    function sig(Offer[1] memory offers) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        return abi.encode(signature(_root, privateKey[offers[0].maker], offers[0].ratifier));
    }

    function sig(Offer[2] memory offers) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        return abi.encode(signature(_root, privateKey[offers[0].maker], offers[0].ratifier));
    }

    function sortCollateralParams(CollateralParams[] memory arr) internal pure returns (CollateralParams[] memory) {
        for (uint256 i = 1; i < arr.length; i++) {
            uint256 j = i;
            while (j > 0 && bytes20(arr[j].token) < bytes20(arr[j - 1].token)) {
                CollateralParams memory temp = arr[j];
                arr[j] = arr[j - 1];
                arr[j - 1] = temp;
                j--;
            }
        }
        return arr;
    }

    /// @dev Returns an allowed LLTV tier based on a seed value.
    function allowedLltv(uint256 seed) internal pure returns (uint256) {
        uint256[9] memory tiers = [LLTV_0, LLTV_1, LLTV_2, LLTV_3, LLTV_4, LLTV_5, LLTV_6, LLTV_7, LLTV_8];
        return tiers[seed % 9];
    }

    /// @dev Returns an obligation with sorted, unique collateralParams, valid lltv/maxLif, and a creatable TTM.
    function validObligation(Obligation memory obligation) internal pure returns (Obligation memory) {
        uint256 len =
            obligation.collateralParams.length > MAX_COLLATERALS ? MAX_COLLATERALS : obligation.collateralParams.length;
        CollateralParams[] memory collateralParams = new CollateralParams[](len);
        for (uint256 i = 0; i < len; i++) {
            collateralParams[i].token =
                address(uint160(uint256(keccak256(abi.encode(obligation.collateralParams[i].token, i)))));
            uint256 lltv = allowedLltv(obligation.collateralParams[i].lltv);
            collateralParams[i].lltv = lltv;
            collateralParams[i].maxLif = maxLif(lltv, LIQUIDATION_CURSOR_LOW);
        }
        collateralParams = sortCollateralParams(collateralParams);
        obligation.collateralParams = collateralParams;
        return obligation;
    }

    function setupObligation(Obligation memory obligation, uint256 units) internal {
        deal(address(loanToken), lender, units); // at tick MAX_TICK, price is 1.

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = units;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp;
        borrowerOffer.tick = MAX_TICK;

        vm.prank(lender);
        midnight.take(
            units,
            lender,
            address(0),
            hex"",
            borrower,
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer])
        );
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function maxLif(uint256 lltv, uint256 cursor) internal pure returns (uint256) {
        return UtilsLib.mulDivDown(WAD, WAD, WAD - UtilsLib.mulDivDown(cursor, WAD - lltv, WAD));
    }
}
