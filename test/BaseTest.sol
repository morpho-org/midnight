// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {ERC20Permit} from "./erc20s/ERC20Permit.sol";
import {ERC20NoRevert} from "./erc20s/ERC20NoRevert.sol";
import {ERC20USDT} from "./erc20s/ERC20USDT.sol";
import {ERC20RevertToZero} from "./erc20s/ERC20RevertToZero.sol";
import {ERC20NoReturn} from "./erc20s/ERC20NoReturn.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
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
    LLTV_8,
    maxTradingFee as _maxTradingFee,
    maxLif as _maxLif
} from "../src/libraries/ConstantsLib.sol";
import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {EcrecoverRatifier} from "../src/ratifiers/EcrecoverRatifier.sol";
import {EcrecoverAuthorizer} from "../src/periphery/EcrecoverAuthorizer.sol";
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
        midnight.setTickSpacingSetter(address(this));

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
            loanToken = ERC20(address(new ERC20NoRevert("loan")));
            collateralToken1 = ERC20(address(new ERC20NoRevert("collat1")));
            collateralToken2 = ERC20(address(new ERC20NoRevert("collat2")));
        } else if (tokenType == 2) {
            loanToken = ERC20(address(new ERC20USDT("loan")));
            collateralToken1 = ERC20(address(new ERC20USDT("collat1")));
            collateralToken2 = ERC20(address(new ERC20USDT("collat2")));
        } else if (tokenType == 3) {
            loanToken = ERC20(address(new ERC20RevertToZero("loan")));
            collateralToken1 = ERC20(address(new ERC20RevertToZero("collat1")));
            collateralToken2 = ERC20(address(new ERC20RevertToZero("collat2")));
        } else if (tokenType == 4) {
            loanToken = ERC20(address(new ERC20NoReturn("loan")));
            collateralToken1 = ERC20(address(new ERC20NoReturn("collat1")));
            collateralToken2 = ERC20(address(new ERC20NoReturn("collat2")));
        } else {
            loanToken = new ERC20Permit("loan", "loan");
            collateralToken1 = new ERC20Permit("collat1", "collat1");
            collateralToken2 = new ERC20Permit("collat2", "collat2");
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

    function collateralize(Market memory market, address _borrower, uint256 debt) internal {
        uint256 oraclePrice = Oracle(market.collateralParams[0].oracle).price();
        uint256 collateral =
            debt.mulDivUp(WAD, market.collateralParams[0].lltv).mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
        deal(address(market.collateralParams[0].token), _borrower, collateral);

        vm.startPrank(_borrower);
        ERC20(market.collateralParams[0].token).approve(address(midnight), 0);
        ERC20(market.collateralParams[0].token).approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, _borrower);
        vm.stopPrank();
    }

    // hardcodes the right root, signature, proof, and callback (no callback)
    function take(uint256 units, address taker, Offer memory offer) internal returns (uint256, uint256) {
        // receiverIfTakerIsSeller param is for taker (when offer.buy == true)
        // offer.receiverIfMakerIsSeller is for maker (when offer.buy == false)
        vm.prank(taker);
        return midnight.take(units, taker, address(0), hex"", taker, offer, merkleRatifierData([offer]));
    }

    function setupOtherUsers(Market memory market, uint256 units) internal {
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 assets = units.mulDivUp(price, WAD);
        deal(address(loanToken), otherLender, assets);

        Offer memory lenderOffer;
        lenderOffer.market = market;
        lenderOffer.buy = true;
        lenderOffer.maker = otherLender;
        lenderOffer.maxUnits = units;
        lenderOffer.group = keccak256(abi.encode("non zero group"));
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        collateralize(market, otherBorrower, units);
        take(units, otherBorrower, lenderOffer);
    }

    function createBadDebt(Market memory market) internal {
        (address badBorrower, uint256 badBorrowerPrivateKey) = makeAddrAndKey("badBorrower");
        privateKey[badBorrower] = badBorrowerPrivateKey;
        address unluckyLender = makeAddr("unluckyLender");
        vm.prank(unluckyLender);
        loanToken.approve(address(midnight), type(uint256).max);
        Offer memory badBorrowerOffer;
        badBorrowerOffer.market = market;
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

        deal(market.collateralParams[0].token, address(this), 135);
        midnight.supplyCollateral(market, 0, 135, badBorrower);

        vm.prank(badBorrower);
        midnight.setIsAuthorized(badBorrower, address(this), false);

        deal(address(loanToken), unluckyLender, 100);

        take(100, unluckyLender, badBorrowerOffer);

        Oracle(market.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(market, 0, 0, 0, badBorrower, address(this), address(0), "");

        // then empty the market (borrow side only).
        vm.prank(badBorrower);
        midnight.setIsAuthorized(badBorrower, address(this), true);
        deal(address(loanToken), address(this), midnight.debtOf(toId(market), badBorrower));
        midnight.repay(market, midnight.debtOf(toId(market), badBorrower), badBorrower, address(0), hex"");
        assertEq(midnight.debtOf(toId(market), badBorrower), 0, "debt");

        // reset the price.
        Oracle(market.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE);
    }

    function toId(Market memory market) internal view returns (bytes32) {
        return IdLib.toId(market, block.chainid, address(midnight));
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = HashLib.hashOffer(offers[1]);
        return _proof;
    }

    // 4 leaves, assumes the offer is the first one
    function proofFirstLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[1]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the second one
    function proofSecondLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[0]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the third one
    function proofThirdLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[3]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the fourth one
    function proofFourthLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[2]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        return _proof;
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return HashLib.hashOffer(offers[0]);
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
    }

    function root(Offer[4] memory offers) internal pure returns (bytes32) {
        bytes32 left = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        bytes32 right = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return HashLib.hashNode(left, right);
    }

    function domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, verifyingContract));
    }

    function signature(bytes32 _root, uint256 _privateKey, address verifyingContract, uint256 height)
        internal
        view
        returns (Signature memory)
    {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), _root));
        bytes32 messageHash = keccak256(bytes.concat("\x19\x01", domainSeparator(verifyingContract), structHash));
        Signature memory _signature;
        (_signature.v, _signature.r, _signature.s) = vm.sign(_privateKey, messageHash);
        return _signature;
    }

    function merkleRatifierData(Offer[1] memory offers, address _signer) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        Signature memory _sig = signature(_root, privateKey[_signer], offers[0].ratifier, 0);
        return abi.encode(_sig, 0, _root, 0, proof(offers));
    }

    function merkleRatifierData(Offer[1] memory offers) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        Signature memory _sig = signature(_root, privateKey[offers[0].maker], offers[0].ratifier, 0);
        return abi.encode(_sig, 0, _root, 0, proof(offers));
    }

    /// @dev Builds merkle ratifier data with explicit root, height, leaf index, and proof.
    function merkleRatifierData(
        Offer memory offer,
        uint256 _height,
        bytes32 _root,
        uint256 _leafIndex,
        bytes32[] memory _proof
    ) internal view returns (bytes memory) {
        Signature memory _sig = signature(_root, privateKey[offer.maker], offer.ratifier, _height);
        return abi.encode(_sig, _height, _root, _leafIndex, _proof);
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

    /// @dev Returns a market with sorted, unique collateralParams, valid lltv/maxLif, and a creatable TTM.
    function validMarket(Market memory market) internal view returns (Market memory) {
        uint256 len =
            market.collateralParams.length > MAX_COLLATERALS ? MAX_COLLATERALS : market.collateralParams.length;
        vm.assume(len > 0);
        CollateralParams[] memory collateralParams = new CollateralParams[](len);
        for (uint256 i = 0; i < len; i++) {
            collateralParams[i].token =
                address(uint160(uint256(keccak256(abi.encode(market.collateralParams[i].token, i)))));
            uint256 lltv = allowedLltv(market.collateralParams[i].lltv);
            collateralParams[i].lltv = lltv;
            collateralParams[i].maxLif = maxLif(lltv, LIQUIDATION_CURSOR_LOW);
        }
        collateralParams = sortCollateralParams(collateralParams);
        market.collateralParams = collateralParams;
        market.maturity = bound(market.maturity, 0, block.timestamp + 100 * 365 days);
        return market;
    }

    function setupMarket(Market memory market, uint256 units) internal {
        deal(address(loanToken), lender, units); // at tick MAX_TICK, price is 1.

        Offer memory borrowerOffer = _setupMarketOffer(market, units);
        bytes memory rd = merkleRatifierData([borrowerOffer]);

        vm.prank(lender);
        midnight.take(units, lender, address(0), hex"", borrower, borrowerOffer, rd);
    }

    function _setupMarketOffer(Market memory market, uint256 units) private view returns (Offer memory borrowerOffer) {
        borrowerOffer.market = market;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = units;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp;
        borrowerOffer.tick = MAX_TICK;
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
        return _maxLif(lltv, cursor);
    }

    function maxTradingFee(uint256 index) internal pure returns (uint256) {
        return _maxTradingFee(index);
    }
}
