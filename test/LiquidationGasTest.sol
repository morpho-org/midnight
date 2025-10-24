// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";

import {console} from "../lib/forge-std/src/console.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest} from "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    /// forge-config: default.isolate = true
    function testLiquidateGas() public {
        uint256 numCollaterals = 10;
        uint256 numSeizures = 10;
        uint256 lltv = 0.75e18;

        // Create collaterals

        Collateral[] memory collaterals = new Collateral[](numCollaterals);
        for (uint256 i = 0; i < collaterals.length; i++) {
            ERC20 collat = new ERC20("collat", "collat");
            collat.approve(address(morphoV2), type(uint256).max);
            collaterals[i] = Collateral({token: address(collat), lltv: lltv, oracle: address(new Oracle())});
        }
        collaterals = sortCollaterals(collaterals);

        // Populate obligation

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals = collaterals;

        uint256 collateral = 1e18;

        for (uint256 i = 0; i < collaterals.length; i++) {
            deal(address(collaterals[i].token), address(this), collateral);

            morphoV2.supplyCollateral(obligation, collaterals[i].token, collateral, borrower);
        }

        deal(address(loanToken), lender, 1e3 * 1e18);

        uint256 maxDebt = collateral * numCollaterals * lltv / 1e18;

        // Create and take offer

        id = toId(obligation);
        Offer memory borrowOffer;
        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = borrower;
        borrowOffer.assets = maxDebt;
        borrowOffer.start = block.timestamp;
        borrowOffer.expiry = block.timestamp + 100;
        borrowOffer.startPrice = 1e18;
        borrowOffer.expiryPrice = 1e18;

        morphoV2.take(
            0,
            0,
            maxDebt,
            0,
            lender,
            borrowOffer,
            sig(root([borrowOffer]), borrowerSecretKey),
            root([borrowOffer]),
            proof([borrowOffer]),
            address(0),
            hex""
        );

        // Setup liquidation
        for (uint256 i = 0; i < numCollaterals; i++) {
            Oracle(collaterals[i].oracle).setPrice(1e36 - 1);
        }
        deal(address(loanToken), address(this), 1e3 * 1e18);

        // Setup seizures

        Seizure[] memory seizures = new Seizure[](numSeizures);
        for (uint256 i = 0; i < numSeizures; i++) {
            seizures[i] = Seizure({collateralIndex: i, repaid: 0, seized: 1});
        }

        morphoV2.liquidate(obligation, seizures, borrower, "");
        console.log("g %s", vm.lastCallGas().gasTotalUsed);
    }
}
