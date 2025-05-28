// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {console} from "../lib/forge-std/src/Test.sol";

import {Oracle} from "./helpers/Oracle.sol";

contract LiquidationTest is BaseTest {
    ERC20 private loanToken;
    uint256 private borrowerSK;
    address private borrower;
    uint256 private lenderSK;
    address private lender;
    address private liquidator;
    Term[] private liquidationTerms;
    Seizure[][] private sN;
    Seizure[][] private sK;

    function genTerm(uint256 n) internal returns (Term memory) {
        Collateral[] memory cs = new Collateral[](n);
        ERC20[] memory tokens = new ERC20[](n);

        for (uint256 i = 0; i < n; i++) {
            tokens[i] = new ERC20("collat", "c", 1 ether);
        }

        tokens = sortTokens(tokens);

        for (uint256 i = 0; i < n; i++) {
            ERC20 c = tokens[i];
            Oracle o = new Oracle();
            c.transfer(borrower, 1 ether);
            cs[i] = Collateral({token: address(tokens[i]), lltv: 0.75e18, oracle: address(o)});
            vm.startPrank(borrower);
            c.approve(address(terms), type(uint256).max);
            vm.stopPrank();
        }

        Term memory t = Term(address(loanToken), cs, block.timestamp + 100);

        loanToken.transfer(lender, 1000);

        vm.startPrank(borrower);
        uint256 remaining = 840;
        uint256 dealt;
        for (uint256 i = 1; i < n; i++) {
            dealt += remaining / (n - 1);
            terms.supplyCollateral(t, cs[i].token, remaining / (n - 1), borrower);
        }
        // The collateral in position 0 is used to make the position liquidatable.
        terms.supplyCollateral(t, cs[0].token, remaining + 500, borrower);
        vm.stopPrank();

        return t;
    }

    function mintBond(Collateral[] memory cs) internal {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: lender,
            assets: 1000,
            loanToken: address(loanToken),
            collaterals: cs,
            maturity: block.timestamp + 100,
            price: 990
        });

        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 1000,
            loanToken: address(loanToken),
            collaterals: cs,
            maturity: block.timestamp + 100,
            price: 990
        });

        Signature memory lendSig = _signOffer(lendOffer, lenderSK);
        Signature memory borrowSig = _signOffer(borrowOffer, borrowerSK);

        terms.MATCH(lendOffer, lendSig, borrowOffer, borrowSig);
    }

    function setUp() public override {
        super.setUp();
        (borrower, borrowerSK) = makeAddrAndKey("borrower");
        (lender, lenderSK) = makeAddrAndKey("lender");
        liquidator = makeAddr("liquidator");

        loanToken = new ERC20("loan", "loan", 1 ether);
        loanToken.transfer(lender, 99);
        loanToken.transfer(borrower, 1);

        vm.prank(lender);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(terms), type(uint256).max);
        vm.prank(liquidator);
        loanToken.approve(address(terms), type(uint256).max);
        vm.stopPrank();

        liquidationTerms = new Term[](10);
        sN = new Seizure[][](10);
        sK = new Seizure[][](10);

        for (uint256 i = 0; i < 10; i++) {
            liquidationTerms[i] = genTerm(i + 1);
            mintBond(liquidationTerms[i].collaterals);
            sK[i] = new Seizure[](10);
            sK[i][0] = Seizure({repaidAmount: 100, seizedAssets: 0});
            for (uint256 k = 1; k < i + 1; k++) {
                sK[i][k] = Seizure({repaidAmount: 0, seizedAssets: 93});
            }
        }

        for (uint256 i = 0; i < 10; i++) {
            liquidationTerms[i] = genTerm(i + 1);
            mintBond(liquidationTerms[i].collaterals);
            sN[i] = new Seizure[](i + 1);
            sN[i][0] = Seizure({repaidAmount: 100, seizedAssets: 0});
            for (uint256 k = 1; k < i + 1; k++) {
                sN[i][k] = Seizure({repaidAmount: 0, seizedAssets: 0});
            }
        }

        vm.warp(block.timestamp + 50);
    }

    function execLiquidation(uint256 k, uint256 n) public {
        loanToken.transfer(liquidator, 1000);
        Term memory t = liquidationTerms[n - 1];
        Oracle(t.collaterals[0].oracle).setPrice(0.25e36);
        vm.prank(liquidator);
        terms.mintAtPar(t, 1000, liquidator);
        vm.prank(liquidator);
        uint256 gasBefore;
        uint256 gasUsed;
        if (n == 10) {
            gasBefore = gasleft();
            terms.liquidate(t, sK[k - 1], borrower, hex"");
            gasUsed = gasBefore - gasleft();
        } else {
            gasBefore = gasleft();
            terms.liquidate(t, sN[n - 1], borrower, hex"");
            gasUsed = gasBefore - gasleft();
        }

        Oracle(t.collaterals[0].oracle).setPrice(1e36);
        emit log_named_uint("Gas used", gasUsed);

        assertEq(ERC20(t.collaterals[0].token).balanceOf(liquidator), 460);
        vm.prank(borrower);
        loanToken.transfer(address(0), loanToken.balanceOf(borrower));
        vm.stopPrank();
        vm.prank(liquidator);
        loanToken.transfer(address(0), loanToken.balanceOf(liquidator));
        vm.stopPrank();
    }

    function testLiquidationN1K1() public {
        execLiquidation(1, 1);
    }

    function testLiquidationN2K1() public {
        execLiquidation(1, 2);
    }

    function testLiquidationN3K1() public {
        execLiquidation(1, 3);
    }

    function testLiquidationN4K1() public {
        execLiquidation(1, 4);
    }

    function testLiquidationN5K1() public {
        execLiquidation(1, 5);
    }

    function testLiquidationN6K1() public {
        execLiquidation(1, 6);
    }

    function testLiquidationN7K1() public {
        execLiquidation(1, 7);
    }

    function testLiquidationN8K1() public {
        execLiquidation(1, 8);
    }

    function testLiquidationN9K1() public {
        execLiquidation(1, 9);
    }

    function testLiquidationN10K1() public {
        execLiquidation(1, 10);
    }

    function testLiquidationN10K2() public {
        execLiquidation(2, 10);
    }

    function testLiquidationN10K3() public {
        execLiquidation(3, 10);
    }

    function testLiquidationN10K4() public {
        execLiquidation(4, 10);
    }

    function testLiquidationN10K5() public {
        execLiquidation(5, 10);
    }

    function testLiquidationN10K6() public {
        execLiquidation(6, 10);
    }

    function testLiquidationN10K7() public {
        execLiquidation(7, 10);
    }

    function testLiquidationN10K8() public {
        execLiquidation(8, 10);
    }

    function testLiquidationN10K9() public {
        execLiquidation(9, 10);
    }

    function testLiquidationN10K10() public {
        execLiquidation(10, 10);
    }
}
