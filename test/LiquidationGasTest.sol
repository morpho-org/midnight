// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    Term internal term;
    bytes32 internal id;

    /// forge-config: default.isolate = true
    function testLiquidateGas() public {
        uint256 numCollaterals = 10;
        uint256 lltv = 0.75e18;

        // Create collaterals

        Collateral[] memory collaterals = new Collateral[](numCollaterals);
        for (uint256 i = 0; i < collaterals.length; i++) {
            ERC20 collat = new ERC20("collat", "collat");
            collat.approve(address(terms), type(uint256).max);
            collaterals[i] = Collateral({token: address(collat), lltv: lltv, oracle: address(new Oracle())});
        }
        collaterals = sortCollaterals(collaterals);

        // Populate term

        term.loanToken = address(loanToken);
        term.maturity = block.timestamp + 100;

        uint256 collateral = 1e18;
        for (uint256 i = 0; i < collaterals.length; i++) {
            term.collaterals.push(collaterals[i]);
        }

        for (uint256 i = 0; i < collaterals.length; i++) {
            deal(address(collaterals[i].token), address(this), collateral);

            terms.supplyCollateral(term, collaterals[i].token, collateral, borrower);
        }

        deal(address(loanToken), lender, 1e3 * 1e18);

        uint256 maxDebt = collateral * numCollaterals * lltv / 1e18;

        // Create and take offer

        id = toId(term);
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: maxDebt,
            loanToken: term.loanToken,
            collaterals: term.collaterals,
            offerStart: block.timestamp,
            offerExpiry: block.timestamp + 100,
            maturity: block.timestamp + 100,
            rate: 0,
            nonce: 0,
            callbackAddress: address(0),
            callbackData: ""
        });

        terms.take(term, maxDebt, lender, borrowOffer, sig(borrowOffer, borrowerSK), address(0), hex"");

        // Setup liquidation
        for (uint256 i = 0; i < numCollaterals; i++) {
            Oracle(collaterals[i].oracle).setPrice(1e36 - 1);
        }
        deal(address(loanToken), address(this), 1e3 * 1e18);

        // Setup seizures

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 0, seizedAssets: 1});

        terms.liquidate(term, seizures, borrower, "");
        console.log("g %s", vm.lastCallGas().gasTotalUsed);
    }
}
