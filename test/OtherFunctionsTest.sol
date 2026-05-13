// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
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

    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);
        market.rcfThreshold = 0;

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(this), true);

        id = toId(market);
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 0, MAX_UNITS);
        additionalCollateral = bound(additionalCollateral, 0, MAX_UNITS);
        address collateralToken = market.collateralParams[0].token;
        collateralize(market, borrower, units);
        setupMarket(market, units);
        deal(collateralToken, address(this), additionalCollateral);
        midnight.supplyCollateral(market, 0, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);

        vm.prank(borrower);
        midnight.withdrawCollateral(market, 0, withdraw, borrower, borrower);

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
        address collateralToken = market.collateralParams[0].token;
        collateralize(market, borrower, units);
        setupMarket(market, units);
        deal(collateralToken, address(this), additionalCollateral);
        midnight.supplyCollateral(market, 0, additionalCollateral, borrower);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.prank(borrower);
        vm.expectRevert(IMidnight.UnhealthyBorrower.selector);
        midnight.withdrawCollateral(market, 0, withdraw, borrower, borrower);
    }

    function testRepay(uint256 units, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        units = bound(units, 0, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        collateralize(market, borrower, units);
        setupMarket(market, units);
        skip(99);
        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        midnight.repay(market, repaid, borrower, address(0), hex"");

        assertEq(midnight.debtOf(id, borrower), units - repaid);
        assertEq(midnight.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(midnight)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testRepayCallback(uint256 units, uint256 repaid, address caller) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 1, units);
        collateralize(market, borrower, units);
        setupMarket(market, units);
        skip(99);

        RepayCallback callback = new RepayCallback();
        deal(address(loanToken), address(callback), repaid);
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, caller, true);
        vm.prank(address(callback));
        loanToken.approve(address(midnight), repaid);

        vm.prank(caller);
        midnight.repay(market, repaid, borrower, address(callback), hex"deadbeef");

        assertEq(midnight.debtOf(id, borrower), units - repaid);
        assertEq(callback.recordedMarketId(), id);
        assertEq(callback.recordedData(), hex"deadbeef");
        assertEq(callback.recordedUnits(), repaid);
        assertEq(callback.recordedOnBehalf(), borrower);
    }

    function testWithdraw(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_UNITS);
        withdraw = bound(withdraw, 1, units);
        testRepay(units, withdraw);

        vm.prank(lender);
        midnight.withdraw(market, withdraw, lender, lender);

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
        midnight.withdraw(market, withdraw, lender, receiver);

        assertEq(loanToken.balanceOf(lender), 0, "balance of lender");
        assertEq(loanToken.balanceOf(receiver), withdraw, "balance of receiver");
    }

    function testWithdrawCollateralToReceiver(uint256 supply, uint256 withdraw) public {
        supply = bound(supply, 1, MAX_UNITS);
        withdraw = bound(withdraw, 1, supply);
        address collateralToken = market.collateralParams[0].token;
        address receiver = makeAddr("receiver");
        deal(collateralToken, address(this), supply);
        midnight.supplyCollateral(market, 0, supply, address(this));

        midnight.withdrawCollateral(market, 0, withdraw, address(this), receiver);

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

    function testTouchMarket(Market memory _market) public {
        vm.assume(_market.collateralParams.length > 0);
        _market = validMarket(_market);

        midnight.setDefaultContinuousFee(_market.loanToken, MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i < 7; i++) {
            midnight.setDefaultTradingFee(_market.loanToken, i, maxTradingFee(i));
        }

        bytes32 _id = midnight.touchMarket(_market);
        assertEq(midnight.tickSpacing(_id) > 0, true, "market created");
        uint16[7] memory fees = midnight.tradingFeeCbps(_id);
        for (uint256 i = 0; i < 7; i++) {
            assertEq(fees[i], midnight.defaultTradingFeeCbp(_market.loanToken, i), "fees");
            assertGt(fees[i], 0, "fee nonzero");
        }
        assertEq(midnight.continuousFee(_id), MAX_CONTINUOUS_FEE, "continuousFee");
    }

    function testToMarket(Market memory _market) public {
        vm.assume(_market.collateralParams.length > 0);
        _market = validMarket(_market);

        bytes32 _id = midnight.touchMarket(_market);
        Market memory marketFromId = midnight.toMarket(_id);
        assertEq(_market.loanToken, marketFromId.loanToken, "loanToken");
        assertEq(_market.maturity, marketFromId.maturity, "maturity");
        assertEq(_market.collateralParams.length, marketFromId.collateralParams.length, "collateralParams length");
        for (uint256 i = 0; i < marketFromId.collateralParams.length; i++) {
            assertEq(_market.collateralParams[i].token, marketFromId.collateralParams[i].token, "collateral token");
            assertEq(_market.collateralParams[i].lltv, marketFromId.collateralParams[i].lltv, "lltv");
            assertEq(_market.collateralParams[i].maxLif, marketFromId.collateralParams[i].maxLif, "maxLif");
            assertEq(_market.collateralParams[i].oracle, marketFromId.collateralParams[i].oracle, "oracle");
        }
    }

    function testToId(Market memory _market) public view {
        _market = validMarket(_market);

        bytes32 expected = toId(_market);
        bytes32 actual = midnight.toId(_market);
        assertEq(actual, expected, "toId mismatch");
    }

    function testToIdStableAcrossHardfork(Market memory _market, Market memory otherMarket, uint64 newChainId) public {
        vm.assume(_market.collateralParams.length > 0);
        vm.assume(newChainId != block.chainid);
        _market = validMarket(_market);

        bytes32 idBefore = midnight.touchMarket(_market);
        uint256 capturedChainId = midnight.INITIAL_CHAIN_ID();

        vm.chainId(newChainId);

        assertEq(midnight.INITIAL_CHAIN_ID(), capturedChainId, "INITIAL_CHAIN_ID changed");
        assertEq(midnight.toId(_market), idBefore, "toId changed");
        Market memory roundTrip = midnight.toMarket(idBefore);
        assertEq(keccak256(abi.encode(roundTrip)), keccak256(abi.encode(_market)), "stored market lost");

        otherMarket = validMarket(otherMarket);
        bytes32 otherId = midnight.touchMarket(otherMarket);
        Market memory otherRoundTrip = midnight.toMarket(otherId);
        assertEq(keccak256(abi.encode(otherRoundTrip)), keccak256(abi.encode(otherMarket)), "stored market lost");
    }

    function testToMarketRevertsIfNotCreated(bytes32 _id) public {
        vm.expectRevert(IMidnight.MarketNotCreated.selector);
        midnight.toMarket(_id);
    }

    function testSstore2CodeStartsWithStop(Market memory _market) public {
        vm.assume(_market.collateralParams.length > 0);
        _market = validMarket(_market);

        bytes32 _id = midnight.touchMarket(_market);
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

        Market memory marketWithRevertingOracle;
        marketWithRevertingOracle.loanToken = address(loanToken);
        marketWithRevertingOracle.maturity = block.timestamp + 100;
        marketWithRevertingOracle.collateralParams = collateralParams;

        // Make the oracle revert.
        revertingOracle.stopOracle();

        deal(address(collateralToken1), address(this), collateral);
        midnight.supplyCollateral(marketWithRevertingOracle, 0, collateral, borrower);
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

        Market memory marketWithRevertingOracle;
        marketWithRevertingOracle.loanToken = address(loanToken);
        marketWithRevertingOracle.maturity = block.timestamp + 100;
        marketWithRevertingOracle.collateralParams = collateralParams;

        deal(address(collateralToken1), address(this), collateral);
        midnight.supplyCollateral(marketWithRevertingOracle, 0, collateral, borrower);

        bytes32 _id = toId(marketWithRevertingOracle);
        assertEq(midnight.collateral(_id, borrower, 0), collateral, "collateral should be set");

        revertingOracle.stopOracle();

        vm.prank(borrower);
        midnight.withdrawCollateral(marketWithRevertingOracle, 0, collateral, borrower, borrower);
    }

    // CollateralBitmap tests.

    function _createMultiCollateralMarket(uint256 numCollaterals) internal returns (Market memory _market) {
        CollateralParams[] memory collateralParams = new CollateralParams[](numCollaterals);
        for (uint256 i = 0; i < numCollaterals; i++) {
            ERC20 token = new ERC20("", "");
            Oracle _oracle = new Oracle();
            collateralParams[i] = CollateralParams({
                token: address(token), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(_oracle)
            });
        }
        collateralParams = sortCollateralParams(collateralParams);
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        _market.collateralParams = collateralParams;
        _market.rcfThreshold = 0;
    }

    function testMaturityTooFar(uint256 maturity) public {
        maturity = bound(maturity, block.timestamp + 100 * 365 days + 1, type(uint256).max);
        Market memory longMarket;
        longMarket.loanToken = address(loanToken);
        longMarket.maturity = maturity;
        longMarket.collateralParams = market.collateralParams;

        vm.expectRevert(IMidnight.MaturityTooFar.selector);
        midnight.touchMarket(longMarket);
    }

    function testZeroCollaterals() public {
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        _market.collateralParams = new CollateralParams[](0);
        vm.expectRevert(IMidnight.NoCollateralParams.selector);
        midnight.touchMarket(_market);
    }

    function testMaxCollaterals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, MAX_COLLATERALS + 1, 1000);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        vm.expectRevert(IMidnight.TooManyCollateralParams.selector);
        midnight.touchMarket(_market);
    }

    function testExactMaxCollaterals() public {
        Market memory _market = _createMultiCollateralMarket(MAX_COLLATERALS);

        bytes32 _id = midnight.touchMarket(_market);
        address sstore2Address = address(uint160(uint256(_id)));
        Market memory marketFromId = midnight.toMarket(_id);

        assertEq(midnight.tickSpacing(_id) > 0, true, "market created");
        assertEq(sstore2Address.code.length, abi.encode(_market).length, "stored market code size");
        assertLt(sstore2Address.code.length, 24_576, "stored market code size below EIP-170 limit");
        assertEq(marketFromId.collateralParams.length, MAX_COLLATERALS, "collateralParams length");
    }

    function testCollateralsNotSorted() public {
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](2);
        collateralParams[0] = CollateralParams({
            token: address(uint160(2)), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        collateralParams[1] = CollateralParams({
            token: address(uint160(1)), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle2)
        });
        _market.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.CollateralParamsNotSorted.selector);
        midnight.touchMarket(_market);
    }

    function testLltvNotAllowedAboveWad(uint256 lltv) public {
        lltv = bound(lltv, WAD + 1, type(uint256).max);
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        _market.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.LltvNotAllowed.selector);
        midnight.touchMarket(_market);
    }

    function testLltvNotAllowedBelowWad() public {
        // 0.5e18 is not an allowed LLTV tier
        uint256 lltv = 0.5e18;
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        _market.collateralParams = collateralParams;
        vm.expectRevert(IMidnight.LltvNotAllowed.selector);
        midnight.touchMarket(_market);
    }

    function testBelowExactMaxCollaterals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, MAX_COLLATERALS - 1);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        midnight.touchMarket(_market);
    }

    function testMaxCollateralsPerBorrower() public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER + 1;
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            address token = _market.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_market, i, 1e18, borrower);
        }

        address lastToken = _market.collateralParams[numCollaterals - 1].token;
        deal(lastToken, address(this), 1e18);
        ERC20(lastToken).approve(address(midnight), 1e18);
        vm.expectRevert(IMidnight.TooManyActivatedCollaterals.selector);
        midnight.supplyCollateral(_market, numCollaterals - 1, 1e18, borrower);
    }

    function testCollateralBitmapCtzSingleCollateral(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        address token = _market.collateralParams[collateralIndex].token;
        deal(token, address(this), 1e18);
        ERC20(token).approve(address(midnight), 1e18);
        midnight.supplyCollateral(_market, collateralIndex, 1e18, borrower);

        uint128 collateralBitmap = midnight.collateralBitmap(toId(_market), borrower);

        assertEq(collateralBitmap, 1 << collateralIndex, "collateralBitmap should have only bit at collateralIndex");
        assertEq(UtilsLib.msb(collateralBitmap), collateralIndex, "msb should equal collateralIndex");
    }

    function testCollateralBitmapCountBitsAfterMultipleSupplies(uint256 k) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        k = bound(k, 1, numCollaterals);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        for (uint256 i = 0; i < k; i++) {
            address token = _market.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_market, i, 1e18, borrower);
        }

        bytes32 _id = toId(_market);
        uint128 collateralBitmap = midnight.collateralBitmap(_id, borrower);
        assertEq(UtilsLib.countBits(collateralBitmap), k, "countBits should equal number of supplied collateralParams");
        assertEq(UtilsLib.msb(collateralBitmap), k - 1, "msb should equal number of supplied collateralParams - 1");
    }

    function testCollateralBitmapClearedOnFullWithdraw(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        // Supply all collateralParams.
        for (uint256 i = 0; i < numCollaterals; i++) {
            address token = _market.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_market, i, 1e18, borrower);
        }

        bytes32 _id = toId(_market);
        assertEq(UtilsLib.countBits(midnight.collateralBitmap(_id, borrower)), numCollaterals, "all bits set");

        // Withdraw one collateral fully.
        vm.prank(borrower);
        midnight.withdrawCollateral(_market, collateralIndex, 1e18, borrower, borrower);

        uint128 collateralBitmap = midnight.collateralBitmap(_id, borrower);
        assertEq(UtilsLib.countBits(collateralBitmap), numCollaterals - 1, "one bit cleared");
        assertEq(collateralBitmap & (1 << collateralIndex), 0, "withdrawn collateral bit should be cleared");
    }

    function testCollateralBitmapClearedOnFullLiquidation(uint256 collateralIndex) public {
        uint256 numCollaterals = MAX_COLLATERALS_PER_BORROWER;
        collateralIndex = bound(collateralIndex, 0, numCollaterals - 1);
        Market memory _market = _createMultiCollateralMarket(numCollaterals);

        for (uint256 i = 0; i < numCollaterals; i++) {
            Oracle(_market.collateralParams[i].oracle).setPrice(ORACLE_PRICE_SCALE);
        }

        for (uint256 i = 0; i < numCollaterals; i++) {
            address token = _market.collateralParams[i].token;
            deal(token, address(this), 1e18);
            ERC20(token).approve(address(midnight), 1e18);
            midnight.supplyCollateral(_market, i, 1e18, borrower);
        }

        bytes32 _id = toId(_market);
        assertEq(UtilsLib.countBits(midnight.collateralBitmap(_id, borrower)), numCollaterals, "all bits set");

        setupMarket(_market, 1e18);

        // Warp to maturity + TIME_TO_MAX_LIF to bypass recovery close factor.
        vm.warp(_market.maturity + TIME_TO_MAX_LIF);

        deal(address(loanToken), address(this), 1e18);
        midnight.liquidate(_market, collateralIndex, 1e18, 0, borrower, address(this), address(0), "");

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

        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] =
            CollateralParams({token: address(collateralToken1), lltv: lltv, maxLif: lif, oracle: address(oracle1)});
        _market.collateralParams = collateralParams;

        vm.expectRevert(IMidnight.InvalidMaxLif.selector);
        midnight.touchMarket(_market);
    }

    function testValidLifCursor025() public {
        uint256 lltv = 0.77e18;
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(lltv, 0.25e18), oracle: address(oracle1)
        });
        _market.collateralParams = collateralParams;

        midnight.touchMarket(_market);
        assertEq(midnight.tickSpacing(toId(_market)) > 0, true, "market created with cursor 0.25");
    }

    function testValidLifCursor05() public {
        uint256 lltv = 0.77e18;
        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 200;
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: lltv, maxLif: maxLif(lltv, 0.5e18), oracle: address(oracle1)
        });
        _market.collateralParams = collateralParams;

        midnight.touchMarket(_market);
        assertEq(midnight.tickSpacing(toId(_market)) > 0, true, "market created with cursor 0.5");
    }

    function testMarketStateGetter(Market memory _market, uint256 _defaultContinuousFee) public {
        vm.assume(_market.collateralParams.length > 0);
        _market = validMarket(_market);
        _defaultContinuousFee = bound(_defaultContinuousFee, 0, MAX_CONTINUOUS_FEE);

        midnight.setDefaultContinuousFee(_market.loanToken, _defaultContinuousFee);
        for (uint256 i = 0; i < 7; i++) {
            midnight.setDefaultTradingFee(_market.loanToken, i, maxTradingFee(i));
        }

        bytes32 _id = midnight.touchMarket(_market);

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
            uint8 tickSpacing
        ) = midnight.marketState(_id);

        uint8 expectedTickSpacing = 4;

        assertEq(totalUnits, 0, "totalUnits");
        assertEq(_lossFactor, 0, "lossFactor");
        assertEq(_withdrawable, 0, "withdrawable");
        assertEq(_continuousFeeCredit, 0, "continuousFeeCredit");
        assertEq(_continuousFee, _defaultContinuousFee, "continuousFee");
        assertEq(tickSpacing, expectedTickSpacing, "tickSpacing");
        assertEq(tradingFeeCbp0, midnight.defaultTradingFeeCbp(_market.loanToken, 0), "tradingFeeCbp0");
        assertEq(tradingFeeCbp1, midnight.defaultTradingFeeCbp(_market.loanToken, 1), "tradingFeeCbp1");
        assertEq(tradingFeeCbp2, midnight.defaultTradingFeeCbp(_market.loanToken, 2), "tradingFeeCbp2");
        assertEq(tradingFeeCbp3, midnight.defaultTradingFeeCbp(_market.loanToken, 3), "tradingFeeCbp3");
        assertEq(tradingFeeCbp4, midnight.defaultTradingFeeCbp(_market.loanToken, 4), "tradingFeeCbp4");
        assertEq(tradingFeeCbp5, midnight.defaultTradingFeeCbp(_market.loanToken, 5), "tradingFeeCbp5");
        assertEq(tradingFeeCbp6, midnight.defaultTradingFeeCbp(_market.loanToken, 6), "tradingFeeCbp6");
    }

    function testMarketStateAfterTrade() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);

        uint256 units = 1e18;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        (uint128 totalUnits,,,,,,,,,,, uint32 _continuousFee, uint8 tickSpacing) = midnight.marketState(id);

        assertEq(totalUnits, units, "totalUnits after trade");
        assertEq(_continuousFee, MAX_CONTINUOUS_FEE, "continuousFee after trade");
        assertEq(tickSpacing, 4, "tickSpacing after trade");
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
    bytes32 public recordedMarketId;
    bytes public recordedData;
    uint256 public recordedUnits;
    address public recordedOnBehalf;

    function repay(Midnight midnight, Market memory market, uint256 units, address onBehalf, bytes memory data)
        external
    {
        ERC20(market.loanToken).approve(address(midnight), units);
        midnight.repay(market, units, onBehalf, address(this), data);
    }

    function onRepay(bytes32 marketId, Market memory market, uint256 units, address onBehalf, bytes memory data)
        external
        returns (bytes32)
    {
        require(marketId == IdLib.toId(market, block.chainid, msg.sender), "wrong marketId");
        recordedMarketId = marketId;
        recordedData = data;
        recordedUnits = units;
        recordedOnBehalf = onBehalf;
        return CALLBACK_SUCCESS;
    }
}
