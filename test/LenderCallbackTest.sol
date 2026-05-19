// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD, LLTV_2} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {VaultLenderCallback} from "../src/periphery/VaultLenderCallback.sol";
import {ObligationLenderCallback} from "../src/periphery/ObligationLenderCallback.sol";

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";

// TODO: use real vault v2
contract MockVault {
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }

    function withdraw(uint256 assets, address receiver, address) external returns (uint256) {
        SafeTransferLib.safeTransfer(asset, receiver, assets);
        return assets;
    }
}

contract VaultLenderCallbackTest is BaseTest {
    using UtilsLib for uint256;

    VaultLenderCallback internal vaultLenderCallback;
    Market internal obligation;
    bytes32 internal id;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        vaultLenderCallback = new VaultLenderCallback(address(midnight));

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.market = obligation;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;
    }

    function testConstructor() public view {
        assertEq(vaultLenderCallback.MIDNIGHT(), address(midnight));
    }

    function testOnBuyVaultV2Maker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 buyerAssets = units.mulDivUp(price, WAD);

        // Deploy mock vault with loan tokens.
        MockVault vault = new MockVault(address(loanToken));
        deal(address(loanToken), address(vault), buyerAssets);

        // Lender makes a buy offer with callback.
        Offer memory lenderOffer;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.callback = address(vaultLenderCallback);
        lenderOffer.callbackData = abi.encode(address(vault));
        lenderOffer.maxUnits = units;
        lenderOffer.market = obligation;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        // Collateralize borrower and take.
        collateralize(obligation, borrower, units);

        take(units, borrower, lenderOffer);

        assertEq(midnight.creditOf(id, lender), units);
        assertEq(midnight.debtOf(id, borrower), units);
        assertEq(loanToken.balanceOf(address(vault)), 0);
    }

    function testOnBuyVaultV2Taker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 buyerAssets = units.mulDivUp(price, WAD);

        // Deploy mock vault with loan tokens.
        MockVault vault = new MockVault(address(loanToken));
        deal(address(loanToken), address(vault), buyerAssets);

        // Borrower makes a sell offer.
        borrowerOffer.maxUnits = units;
        collateralize(obligation, borrower, units);

        // Lender takes via taker callback.
        vm.prank(lender);
        midnight.take(
            units,
            lender,
            address(vaultLenderCallback),
            abi.encode(address(vault)),
            address(0),
            borrowerOffer,
            merkleRatifierData([borrowerOffer])
        );

        assertEq(midnight.creditOf(id, lender), units);
        assertEq(midnight.debtOf(id, borrower), units);
        assertEq(loanToken.balanceOf(address(vault)), 0);
    }

    function testOnBuyUnauthorized() public {
        Market memory ob;
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("unauthorized");
        vaultLenderCallback.onBuy(bytes32(0), ob, address(0), 0, 0, "");
    }
}

contract ObligationLenderCallbackTest is BaseTest {
    using UtilsLib for uint256;

    ObligationLenderCallback internal obligationLenderCallback;
    Market internal obligation;
    bytes32 internal id;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        obligationLenderCallback = new ObligationLenderCallback(address(midnight));

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.market = obligation;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;
    }

    function testConstructor() public view {
        assertEq(obligationLenderCallback.MIDNIGHT(), address(midnight));
    }

    /// @dev Helper to set up obligation2 with lender credit and withdrawable funds.
    function _setupMidnightSource(uint256 buyerAssets) internal returns (Market memory obligation2, bytes32 id2) {
        obligation2.loanToken = address(loanToken);
        obligation2.maturity = block.timestamp + 200;
        obligation2.collateralParams = obligation.collateralParams;
        obligation2.rcfThreshold = 0;
        id2 = toId(obligation2);

        // Collateralize borrower on obligation2 and lend.
        collateralize(obligation2, borrower, buyerAssets);
        deal(address(loanToken), lender, buyerAssets);

        Offer memory lenderOffer2;
        lenderOffer2.buy = true;
        lenderOffer2.maker = lender;
        lenderOffer2.maxUnits = buyerAssets;
        lenderOffer2.market = obligation2;
        lenderOffer2.ratifier = address(ecrecoverRatifier);
        lenderOffer2.expiry = block.timestamp + 300;
        lenderOffer2.tick = MAX_TICK;
        lenderOffer2.group = keccak256("obligation2");

        take(buyerAssets, borrower, lenderOffer2);

        // Borrower repays to create withdrawable funds.
        deal(address(loanToken), borrower, buyerAssets);
        vm.prank(borrower);
        midnight.repay(obligation2, buyerAssets, borrower, address(0), hex"");

        // Authorize callback to withdraw on behalf of lender.
        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(obligationLenderCallback), true);
    }

    function testOnBuyMidnightMaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 buyerAssets = units.mulDivUp(price, WAD);

        (, bytes32 id2) = _setupMidnightSource(buyerAssets);

        // Lender makes a buy offer on obligation with callback.
        Offer memory lenderOffer;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.callback = address(obligationLenderCallback);
        lenderOffer.callbackData = abi.encode(address(uint160(uint256(id2))));
        lenderOffer.maxUnits = units;
        lenderOffer.market = obligation;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        // Collateralize borrower on obligation and take.
        collateralize(obligation, borrower, units);

        take(units, borrower, lenderOffer);

        assertEq(midnight.creditOf(id, lender), units);
        assertEq(midnight.debtOf(id, borrower), units);
        assertEq(midnight.creditOf(id2, lender), 0);
    }

    function testOnBuyMidnightTaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 buyerAssets = units.mulDivUp(price, WAD);

        (, bytes32 id2) = _setupMidnightSource(buyerAssets);

        // Borrower makes a sell offer.
        borrowerOffer.maxUnits = units;
        collateralize(obligation, borrower, units);

        // Lender takes via taker callback.
        vm.prank(lender);
        midnight.take(
            units,
            lender,
            address(obligationLenderCallback),
            abi.encode(address(uint160(uint256(id2)))),
            address(0),
            borrowerOffer,
            merkleRatifierData([borrowerOffer])
        );

        assertEq(midnight.creditOf(id, lender), units);
        assertEq(midnight.debtOf(id, borrower), units);
        assertEq(midnight.creditOf(id2, lender), 0);
    }

    function testOnBuyUnauthorized() public {
        Market memory ob;
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("unauthorized");
        obligationLenderCallback.onBuy(bytes32(0), ob, address(0), 0, 0, "");
    }
}
