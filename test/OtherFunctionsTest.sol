// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Obligation, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {
    IBuyCallback,
    ISellCallback,
    ILiquidateCallback,
    IRepayCallback,
    IFlashLoanCallback
} from "../src/interfaces/ICallbacks.sol";
import {Midnight} from "../src/Midnight.sol";
import {IdLib} from "../src/libraries/IdLib.sol";

import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {RevertingOracle} from "./helpers/RevertingOracle.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {
    MAX_COLLATERALS,
    MAX_COLLATERALS_PER_BORROWER,
    MAX_CONTINUOUS_FEE,
    WAD,
    ORACLE_PRICE_SCALE,
    TIME_TO_MAX_LIF,
    CALLBACK_SUCCESS
} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

// Collateral = units / lltv (~1.33x). Some tests add additional collateral on top.
// To keep total collateral within uint128, we cap amounts at type(uint128).max / 3.
uint256 constant MAX_UNITS = MAX_TEST_AMOUNT / 3;

contract OtherFunctionsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(this), true);

        id = toId(obligation);
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 0, MAX_UNITS);
        additionalCollateral = bound(additionalCollateral, 0, MAX_UNITS);
        address collateralToken = obligation.collateralParams[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        midnight.supplyCollateral(obligation, 0, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);

        vm.prank(borrower);
        midnight.withdrawCollateral(obligation, 0, withdraw, borrower, borrower);

        assertEq(midnight.collateral(id, borrower, 0), initialCollateral - withdraw, "collateral of");
        assertEq(
            ERC20(collateralToken).balanceOf(address(midnight)), initialCollateral - withdraw, "balance of midnight"
        );
        assertEq(ERC20(collateralToken).balanceOf(borrower), withdraw, "balance of borrower");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 1, MAX_UNITS);
        additionalCollateral = bound(additionalCollateral, 0, MAX_UNITS);
        address collateralToken = obligation.collateralParams[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        midnight.supplyCollateral(obligation, 0, additionalCollateral, borrower);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.prank(borrower);
        vm.expectRevert(IMidnight.UnhealthyBorrower.selector);
        midnight.withdrawCollateral(obligation, 0, withdraw, borrower, borrower);
    }

    function testRepay(uint256 units, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        units = bound(units, 0, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        skip(99);
        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        midnight.repay(obligation, repaid, borrower, address(0), hex"");

        assertEq(midnight.debtOf(id, borrower), units - repaid);
        assertEq(midnight.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(midnight)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testRepayCallback(uint256 units, uint256 repaid, address caller) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 1, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        skip(99);

        RepayCallback callback = new RepayCallback();
        deal(address(loanToken), address(callback), repaid);
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, caller, true);
        vm.prank(address(callback));
        loanToken.approve(address(midnight), repaid);

        vm.prank(caller);
        midnight.repay(obligation, repaid, borrower, address(callback), hex"deadbeef");

        assertEq(midnight.debtOf(id, borrower), units - repaid);
        assertEq(callback.recordedObligationId(), id);
        assertEq(callback.recordedData(), hex"deadbeef");
        assertEq(callback.recordedUnits(), repaid);
        assertEq(callback.recordedOnBehalf(), borrower);
    }

    function testWithdraw(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_UNITS);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);

        vm.prank(lender);
        midnight.withdraw(obligation, withdraw, lender, lender);

        assertEq(midnight.creditOf(id, lender), units - withdraw, "creditOf");
        assertEq(midnight.withdrawable(id), 0, "withdrawable");
        assertEq(midnight.totalUnits(id), units - withdraw, "totalUnits");
        assertEq(loanToken.balanceOf(address(midnight)), 0, "balance of midnight");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawToReceiver(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_UNITS);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);
        address receiver = makeAddr("receiver");

        vm.prank(lender);
        midnight.withdraw(obligation, withdraw, lender, receiver);

        assertEq(loanToken.balanceOf(lender), 0, "balance of lender");
        assertEq(loanToken.balanceOf(receiver), withdraw, "balance of receiver");
    }

    function testWithdrawCollateralToReceiver(uint256 supply, uint256 withdraw) public {
        supply = bound(supply, 1, MAX_UNITS);
        withdraw = bound(withdraw, 1, supply);
        address collateralToken = obligation.collateralParams[0].token;
        address receiver = makeAddr("receiver");
        deal(collateralToken, address(this), supply);
        midnight.supplyCollateral(obligation, 0, supply, address(this));

        midnight.withdrawCollateral(obligation, 0, withdraw, address(this), receiver);

        assertEq(ERC20(collateralToken).balanceOf(address(this)), 0, "balance of this");
        assertEq(ERC20(collateralToken).balanceOf(receiver), withdraw, "balance of receiver");
    }

    function testSetConsumed(address user, bytes32 group, uint256 amount) public {
        vm.prank(user);
        midnight.setConsumed(group, amount, user);
        assertEq(midnight.consumed(user, group), amount, "consumed");
    }

    function testSetConsumedIncreasing(address user, bytes32 group, uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 0, type(uint256).max - 1);
        amount1 = bound(amount1, amount0, type(uint256).max);

        vm.prank(user);
        midnight.setConsumed(group, amount0, user);
        assertEq(midnight.consumed(user, group), amount0, "consumed 0");

        vm.prank(user);
        midnight.setConsumed(group, amount1, user);
        assertEq(midnight.consumed(user, group), amount1, "consumed 1");
    }

    function testSetConsumedDecreasingReverts(address user, bytes32 group, uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1, type(uint256).max);
        amount1 = bound(amount1, 0, amount0 - 1);

        vm.prank(user);
        midnight.setConsumed(group, amount0, user);

        vm.prank(user);
        vm.expectRevert(IMidnight.AlreadyConsumed.selector);
        midnight.setConsumed(group, amount1, user);
    }

    function testTouchObligation(Obligation memory _obligation) public {
        vm.assume(_obligation.collateralParams.length > 0);
        _obligation = validObligation(_obligation);

        midnight.setDefaultContinuousFee(_obligation.loanToken, MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i < 7; i++) {
            midnight.setDefaultTradingFee(_obligation.loanToken, i, maxTradingFee(i));
        }

        bytes32 _id = midnight.touchObligation(_obligation);
        assertEq(midnight.obligationCreated(_id), true, "obligation created");
        uint16[7] memory fees = midnight.tradingFeeCbps(_id);
        for (uint256 i = 0; i < 7; i++) {
            assertEq(fees[i], midnight.defaultTradingFeeCbp(_obligation.loanToken, i), "fees");
            assertGt(fees[i], 0, "fee nonzero");
        }
        assertEq(midnight.continuousFee(_id), MAX_CONTINUOUS_FEE, "continuousFee");
    }

    function testToObligation(Obligation memory _obligation) public {
        vm.assume(_obligation.collateralParams.length > 0);
        _obligation = validObligation(_obligation);

        bytes32 _id = midnight.touchObligation(_obligation);
        Obligation memory obligationFromId = midnight.toObligation(_id);
        assertEq(_obligation.loanToken, obligationFromId.loanToken, "loanToken");
        assertEq(_obligation.maturity, obligationFromId.maturity, "maturity");
        assertEq(
            _obligation.collateralParams.length, obligationFromId.collateralParams.length, "collateralParams length"
        );
        for (uint256 i = 0; i < obligationFromId.collateralParams.length; i++) {
            assertEq(
                _obligation.collateralParams[i].token, obligationFromId.collateralParams[i].token, "collateral token"
            );
            assertEq(_obligation.collateralParams[i].lltv, obligationFromId.collateralParams[i].lltv, "lltv");
            assertEq(_obligation.collateralParams[i].maxLif, obligationFromId.collateralParams[i].maxLif, "maxLif");
            assertEq(_obligation.collateralParams[i].oracle, obligationFromId.collateralParams[i].oracle, "oracle");
        }
    }

    function testToId(Obligation memory _obligation) public view {
        _obligation = validObligation(_obligation);

        bytes32 expected = toId(_obligation);
        bytes32 actual = midnight.toId(_obligation);
        assertEq(actual, expected, "toId mismatch");
    }

    function testToIdStableAcrossHardfork(
        Obligation memory _obligation,
        Obligation memory otherObligation,
        uint64 newChainId
    ) public {
        vm.assume(_obligation.collateralParams.length > 0);
        vm.assume(newChainId != block.chainid);
        _obligation = validObligation(_obligation);

        bytes32 idBefore = midnight.touchObligation(_obligation);
        uint256 capturedChainId = midnight.INITIAL_CHAIN_ID();

        vm.chainId(newChainId);

        assertEq(midnight.INITIAL_CHAIN_ID(), capturedChainId, "INITIAL_CHAIN_ID changed");
        assertEq(midnight.toId(_obligation), idBefore, "toId changed");
        Obligation memory roundTrip = midnight.toObligation(idBefore);
        assertEq(keccak256(abi.encode(roundTrip)), keccak256(abi.encode(_obligation)), "stored obligation lost");

        otherObligation = validObligation(otherObligation);
        bytes32 otherId = midnight.touchObligation(otherObligation);
        Obligation memory otherRoundTrip = midnight.toObligation(otherId);
        assertEq(
            keccak256(abi.encode(otherRoundTrip)), keccak256(abi.encode(otherObligation)), "stored obligation lost"
        );
    }

    function testToObligationRevertsIfNotCreated(bytes32 _id) public {
        vm.expectRevert(IMidnight.ObligationNotCreated.selector);
        midnight.toObligation(_id);
    }

    function testSstore2CodeStartsWithStop(Obligation memory _obligation) public {
        vm.assume(_obligation.collateralParams.length > 0);
        _obligation = validObligation(_obligation);

        bytes32 _id = midnight.touchObligation(_obligation);
        address sstore2Address = address(uint160(uint256(_id)));

        assertGt(sstore2Address.code.length, 0, "code should exist");
        assertEq(uint8(sstore2Address.code[0]), 0x00, "first byte should be STOP opcode");
    }

    function testSupplyCollateralDoesNotCallOracle(uint256 collateral) public {
        collateral = bound(collateral, 0, MAX_TEST_AMOUNT);
        RevertingOracle revertingOracle = new RevertingOracle();
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1),
            lltv: 0.77e18,
            maxLif: maxLif(0.77e18, 0.25e18),
            oracle: address(revertingOracle)
        });

        Obligation memory obligationWithRevertingOracle;
        obligationWithRevertingOracle.loanToken = address(loanToken);
        obligationWithRevertingOracle.maturity = block.timestamp + 100;
        obligationWithRevertingOracle.collateralParams = collateralParams;

        // Make the oracle revert.
        revertingOracle.stopOracle();

        deal(address(collateralToken1), address(this), collateral);
        midnight.supplyCollateral(obligationWithRevertingOracle, 0, collateral, borrower);
    }

    function testWithdrawCollateralToZeroDoesNotCallOracle(uint256 collateral) public {
        collateral = bound(collateral, 0, MAX_TEST_AMOUNT);

        RevertingOracle revertingOracle = new RevertingOracle();
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1),
            lltv: 0.77e18,
            maxLif: maxLif(0.77e18, 0.25e18),
            oracle: address(revertingOracle)
        });

        Obligation memory obligationWithRevertingOracle;
        obligationWithRevertingOracle.loanToken = address(loanToken);
        obligationWithRevertingOracle.maturity = block.timestamp + 100;
        obligationWithRevertingOracle.collateralParams = collateralParams;

        deal(address(collateralToken1), address(this), collateral);
        midnight.supplyCollateral(obligationWithRevertingOracle, 0, collateral, borrower);

        bytes32 _id = toId(obligationWithRevertingOracle);
        assertEq(midnight.collateral(_id, borrower, 0), collateral, "collateral should be set");

        revertingOracle.stopOracle();

        vm.prank(borrower);
        midnight.withdrawCollateral(obligationWithRevertingOracle, 0, collateral, borrower, borrower);
    }

    // CollateralBitmap tests.

    function _createMultiCollateralObligation(uint256 numCollaterals) internal returns (Obligation memory _obligation) {
        CollateralParams[] memory collateralParams = new CollateralParams[](numCollaterals);
        for (uint256 i = 0; i < numCollaterals; i++) {
            ERC20 token = new ERC20("", "");
            Oracle _oracle = new Oracle();
            collateralParams[i] = CollateralParams({
                token: address(token), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(_oracle)
            });
        }
        collateralParams = sortCollateralParams(collateralParams);
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        _obligation.collateralParams = collateralParams;
        _obligation.rcfThreshold = 0;
    }

    function testMaturityTooFar(uint256 maturity) public {
        maturity = bound(maturity, block.timestamp + 100 * 365 days + 1, type(uint256).max);
        Obligation memory longObligation;
        longObligation.loanToken = address(loanToken);
        longObligation.maturity = maturity;
        longObligation.collateralParams = obligation.collateralParams;

        vm.expectRevert(IMidnight.MaturityTooFar.selector);
        midnight.touchObligation(longObligation);
    }

    function testZeroCollaterals() public {
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        _obligation.collateralParams = new CollateralParams[](0);
        vm.expectRevert(IMidnight.NoCollateralParams.selector);
        midnight.touchObligation(_obligation);
    }

    function testMaxCollaterals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, MAX_COLLATERALS + 1, 1000);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        vm.expectRevert(IMidnight.TooManyCollateralParams.selector);
        midnight.touchObligation(_obligation);
    }

    function testExactMaxCollaterals() public {
        Obligation memory _obligation = _createMultiCollateralObligation(MAX_COLLATERALS);

        bytes32 _id = midnight.touchObligation(_obligation);
        address sstore2Address = address(uint160(uint256(_id)));
        Obligation memory obligationFromId = midnight.toObligation(_id);

        assertEq(midnight.obligationCreated(_id), true, "obligation created");
        assertEq(sstore2Address.code.length, abi.encode(_obligation).length, "stored obligation code size");
        assertLt(sstore2Address.code.length, 24_576, "stored obligation code size below EIP-170 limit");
        assertEq(obligationFromId.collateralParams.length, MAX_COLLATERALS, "collateralParams length");
    }

    function testCollateralsNotSorted() public {
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](2);
        collateralParams[0] = CollateralParams({
            token: address(uint160(2)), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        collateralParams[1] = CollateralParams({
            token: address(uint160(1)), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle2)
        });
        _obligation.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.CollateralParamsNotSorted.selector);
        midnight.touchObligation(_obligation);
    }

    function testLltvNotAllowedAboveWad(uint256 lltv) public {
        lltv = bound(lltv, WAD + 1, type(uint256).max);
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        _obligation.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.LltvNotAllowed.selector);
        midnight.touchObligation(_obligation);
    }

    function testLltvNotAllowedBelowWad() public {
        // 0.5e18 is not an allowed LLTV tier
        uint256 lltv = 0.5e18;
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        _obligation.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.LltvNotAllowed.selector);
        midnight.touchObligation(_obligation);
    }

    function testBelowExactMaxCollaterals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, MAX_COLLATERALS - 1);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        midnight.touchObligation(_obligation);
    }

    function testMaxCollateralsPerBorrower() public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER + 1;
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            address token = _obligation.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_obligation, i, 1e18, borrower);
        }

        address lastToken = _obligation.collateralParams[numCollaterals - 1].token;
        deal(lastToken, address(this), 1e18);
        ERC20(lastToken).approve(address(midnight), 1e18);
        vm.expectRevert(IMidnight.TooManyActivatedCollaterals.selector);
        midnight.supplyCollateral(_obligation, numCollaterals - 1, 1e18, borrower);
    }

    function testCollateralBitmapCtzSingleCollateral(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        address token = _obligation.collateralParams[collateralIndex].token;
        deal(token, address(this), 1e18);
        ERC20(token).approve(address(midnight), 1e18);
        midnight.supplyCollateral(_obligation, collateralIndex, 1e18, borrower);

        uint128 collateralBitmap = midnight.collateralBitmap(toId(_obligation), borrower);

        assertEq(collateralBitmap, 1 << collateralIndex, "collateralBitmap should have only bit at collateralIndex");
        assertEq(UtilsLib.msb(collateralBitmap), collateralIndex, "msb should equal collateralIndex");
    }

    function testCollateralBitmapCountBitsAfterMultipleSupplies(uint256 k) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        k = bound(k, 1, numCollaterals);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        for (uint256 i = 0; i < k; i++) {
            address token = _obligation.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_obligation, i, 1e18, borrower);
        }

        bytes32 _id = toId(_obligation);
        uint128 collateralBitmap = midnight.collateralBitmap(_id, borrower);
        assertEq(UtilsLib.countBits(collateralBitmap), k, "countBits should equal number of supplied collateralParams");
        assertEq(UtilsLib.msb(collateralBitmap), k - 1, "msb should equal number of supplied collateralParams - 1");
    }

    function testCollateralBitmapClearedOnFullWithdraw(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        // Supply all collateralParams.
        for (uint256 i = 0; i < numCollaterals; i++) {
            address token = _obligation.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_obligation, i, 1e18, borrower);
        }

        bytes32 _id = toId(_obligation);
        assertEq(UtilsLib.countBits(midnight.collateralBitmap(_id, borrower)), numCollaterals, "all bits set");

        // Withdraw one collateral fully.
        vm.prank(borrower);
        midnight.withdrawCollateral(_obligation, collateralIndex, 1e18, borrower, borrower);

        uint128 collateralBitmap = midnight.collateralBitmap(_id, borrower);
        assertEq(UtilsLib.countBits(collateralBitmap), numCollaterals - 1, "one bit cleared");
        assertEq(collateralBitmap & (1 << collateralIndex), 0, "withdrawn collateral bit should be cleared");
    }

    function testCollateralBitmapClearedOnFullLiquidation(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Obligation memory _obligation = _createMultiCollateralObligation(numCollaterals);

        for (uint256 i = 0; i < numCollaterals; i++) {
            Oracle(_obligation.collateralParams[i].oracle).setPrice(ORACLE_PRICE_SCALE);
        }

        for (uint256 i = 0; i < numCollaterals; i++) {
            address token = _obligation.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_obligation, i, 1e18, borrower);
        }

        bytes32 _id = toId(_obligation);
        assertEq(UtilsLib.countBits(midnight.collateralBitmap(_id, borrower)), numCollaterals, "all bits set");

        setupObligation(_obligation, 1e18);

        // Warp to maturity + TIME_TO_MAX_LIF to bypass recovery close factor.
        vm.warp(_obligation.maturity + TIME_TO_MAX_LIF);

        deal(address(loanToken), address(this), 1e18);
        midnight.liquidate(_obligation, collateralIndex, 1e18, 0, borrower, address(this), address(0), "");

        uint128 collateralBitmap = midnight.collateralBitmap(_id, borrower);
        assertEq(UtilsLib.countBits(collateralBitmap), numCollaterals - 1, "one bit cleared");
        assertEq(collateralBitmap & (1 << collateralIndex), 0, "liquidated collateral bit should be cleared");
    }

    // LIF validation tests.

    function testInvalidLif(uint256 lif) public {
        lif = bound(lif, 0, type(uint256).max);
        uint256 lltv = 0.77e18;
        vm.assume(lif != maxLif(lltv, 0.25e18));
        vm.assume(lif != maxLif(lltv, 0.5e18));

        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] =
            CollateralParams({token: address(collateralToken1), lltv: lltv, maxLif: lif, oracle: address(oracle1)});
        _obligation.collateralParams = collateralParams;

        vm.expectRevert(IMidnight.InvalidMaxLif.selector);
        midnight.touchObligation(_obligation);
    }

    function testValidLifCursor025() public {
        uint256 lltv = 0.77e18;
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(lltv, 0.25e18), oracle: address(oracle1)
        });
        _obligation.collateralParams = collateralParams;

        midnight.touchObligation(_obligation);
        assertEq(midnight.obligationCreated(toId(_obligation)), true, "obligation created with cursor 0.25");
    }

    function testValidLifCursor05() public {
        uint256 lltv = 0.77e18;
        Obligation memory _obligation;
        _obligation.loanToken = address(loanToken);
        _obligation.maturity = block.timestamp + 200;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(lltv, 0.5e18), oracle: address(oracle1)
        });
        _obligation.collateralParams = collateralParams;

        midnight.touchObligation(_obligation);
        assertEq(midnight.obligationCreated(toId(_obligation)), true, "obligation created with cursor 0.5");
    }

    function testObligationStateGetter(Obligation memory _obligation, uint256 _defaultContinuousFee) public {
        vm.assume(_obligation.collateralParams.length > 0);
        _obligation = validObligation(_obligation);
        _defaultContinuousFee = bound(_defaultContinuousFee, 0, MAX_CONTINUOUS_FEE);

        midnight.setDefaultContinuousFee(_obligation.loanToken, _defaultContinuousFee);
        for (uint256 i = 0; i < 7; i++) {
            midnight.setDefaultTradingFee(_obligation.loanToken, i, maxTradingFee(i));
        }

        bytes32 _id = midnight.touchObligation(_obligation);

        (
            uint128 totalUnits,
            uint128 _lossFactor,
            uint128 _withdrawable,
            uint128 _continuousFeeCredit,
            uint16 tradingFeeCbp0,
            uint16 tradingFeeCbp1,
            uint16 tradingFeeCbp2,
            uint16 tradingFeeCbp3,
            uint16 tradingFeeCbp4,
            uint16 tradingFeeCbp5,
            uint16 tradingFeeCbp6,
            uint32 _continuousFee,
            bool created
        ) = midnight.obligationState(_id);

        assertTrue(created, "obligation should be created");
        assertEq(totalUnits, 0, "totalUnits");
        assertEq(_lossFactor, 0, "lossFactor");
        assertEq(_withdrawable, 0, "withdrawable");
        assertEq(_continuousFeeCredit, 0, "continuousFeeCredit");
        assertEq(_continuousFee, _defaultContinuousFee, "continuousFee");
        assertEq(tradingFeeCbp0, midnight.defaultTradingFeeCbp(_obligation.loanToken, 0), "tradingFeeCbp0");
        assertEq(tradingFeeCbp1, midnight.defaultTradingFeeCbp(_obligation.loanToken, 1), "tradingFeeCbp1");
        assertEq(tradingFeeCbp2, midnight.defaultTradingFeeCbp(_obligation.loanToken, 2), "tradingFeeCbp2");
        assertEq(tradingFeeCbp3, midnight.defaultTradingFeeCbp(_obligation.loanToken, 3), "tradingFeeCbp3");
        assertEq(tradingFeeCbp4, midnight.defaultTradingFeeCbp(_obligation.loanToken, 4), "tradingFeeCbp4");
        assertEq(tradingFeeCbp5, midnight.defaultTradingFeeCbp(_obligation.loanToken, 5), "tradingFeeCbp5");
        assertEq(tradingFeeCbp6, midnight.defaultTradingFeeCbp(_obligation.loanToken, 6), "tradingFeeCbp6");
    }

    function testObligationStateAfterTrade() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);

        uint256 units = 1e18;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        (uint128 totalUnits,,,,,,,,,,, uint32 _continuousFee, bool created) = midnight.obligationState(id);

        assertTrue(created, "should be created");
        assertEq(totalUnits, units, "totalUnits after trade");
        assertEq(_continuousFee, MAX_CONTINUOUS_FEE, "continuousFee after trade");
    }

    function testMidnightRevertsOnCallbacks(address msgSender, bytes calldata data) public {
        bytes4[5] memory selectors = [
            IBuyCallback.onBuy.selector,
            ISellCallback.onSell.selector,
            ILiquidateCallback.onLiquidate.selector,
            IRepayCallback.onRepay.selector,
            IFlashLoanCallback.onFlashLoan.selector
        ];
        for (uint256 i = 0; i < selectors.length; i++) {
            vm.prank(msgSender);
            (bool success,) = address(midnight).call(abi.encodePacked(selectors[i], data));
            assertFalse(success);
        }
    }
}

contract RepayCallback {
    bytes32 public recordedObligationId;
    bytes public recordedData;
    uint256 public recordedUnits;
    address public recordedOnBehalf;

    function repay(Midnight midnight, Obligation memory obligation, uint256 units, address onBehalf, bytes memory data)
        external
    {
        ERC20(obligation.loanToken).approve(address(midnight), units);
        midnight.repay(obligation, units, onBehalf, address(this), data);
    }

    function onRepay(
        bytes32 obligationId,
        Obligation memory obligation,
        uint256 units,
        address onBehalf,
        bytes memory data
    ) external returns (bytes32) {
        require(obligationId == IdLib.toId(obligation, block.chainid, msg.sender), "wrong obligationId");
        recordedObligationId = obligationId;
        recordedData = data;
        recordedUnits = units;
        recordedOnBehalf = onBehalf;
        return CALLBACK_SUCCESS;
    }
}
