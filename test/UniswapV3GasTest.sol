// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    TIME_TO_MAX_LIF,
    LIQUIDATION_CURSOR_LOW,
    CALLBACK_SUCCESS,
    MAX_COLLATERALS_PER_BORROWER
} from "../src/libraries/ConstantsLib.sol";
import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {ILiquidateCallback} from "../src/interfaces/ICallbacks.sol";
import {BaseTest} from "./BaseTest.sol";
import {ERC20NoRevert} from "./erc20s/ERC20NoRevert.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {console} from "forge-std/console.sol";
import {IUniswapV3Factory} from "../lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "../lib/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "../lib/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

// sqrtPriceX96 for a 1:1 token price (sqrt(1) * 2^96)
uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
// Price limits for swaps – one tick past the extreme ticks used in Uniswap TickMath
uint160 constant UNI_MIN_SQRT_RATIO = 4295128739;
uint160 constant UNI_MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
// Full-range tick bounds for a 3000 bps (tickSpacing=60) pool
int24 constant TICK_LOWER = -887220;
int24 constant TICK_UPPER = 887220;

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Self-funding liquidator: receives seized collateral, swaps it for loan tokens on a
/// Uniswap V3 pool inside the Morpho liquidation callback, then lets Morpho pull the repayment
/// from this contract (payer = callback when callback != address(0)).
contract UniV3Liquidator is ILiquidateCallback, IUniswapV3SwapCallback, IUniswapV3MintCallback {
    IMidnight public immutable midnight;
    IUniswapV3Pool public immutable pool;
    address public immutable token0;
    address public immutable token1;

    constructor(address _midnight, address _pool) {
        midnight = IMidnight(_midnight);
        pool = IUniswapV3Pool(_pool);
        token0 = IUniswapV3Pool(_pool).token0();
        token1 = IUniswapV3Pool(_pool).token1();
        // Pre-approve Morpho so it can pull repaid loan tokens after the swap
        IERC20Minimal(token0).approve(_midnight, type(uint256).max);
        IERC20Minimal(token1).approve(_midnight, type(uint256).max);
    }

    /// @notice Adds full-range liquidity to the pool (used during test setup).
    function provideLiquidity(uint128 amount) external {
        pool.mint(address(this), TICK_LOWER, TICK_UPPER, amount, "");
    }

    // ── Morpho liquidation callback
    // ───────────────────────────────────────────

    function onLiquidate(
        bytes32,
        Market memory market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256, // repaidUnits – not needed; Morpho pulls directly from this contract
        uint256,
        address,
        address,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == address(midnight));

        // Swap the seized collateral (already in this contract) for loan tokens.
        // The loan tokens cover the repayment that Morpho will pull after we return.
        address collateral = market.collateralParams[collateralIndex].token;
        bool zeroForOne = collateral == token0;
        uint160 sqrtPriceLimitX96 = zeroForOne ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1;

        pool.swap(address(this), zeroForOne, int256(seizedAssets), sqrtPriceLimitX96, "");

        return CALLBACK_SUCCESS;
    }

    // ── Uniswap V3 callbacks
    // ──────────────────────────────────────────────────

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(pool));
        if (amount0Delta > 0) IERC20Minimal(token0).transfer(address(pool), uint256(amount0Delta));
        else if (amount1Delta > 0) IERC20Minimal(token1).transfer(address(pool), uint256(amount1Delta));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        require(msg.sender == address(pool));
        if (amount0Owed > 0) IERC20Minimal(token0).transfer(address(pool), amount0Owed);
        if (amount1Owed > 0) IERC20Minimal(token1).transfer(address(pool), amount1Owed);
    }
}

/// @notice Two-hop liquidator: swaps seized collateral A → B on poolAB, then B → C (loan token)
/// on poolBC, covering repayment without any upfront capital.
contract UniV3TwoHopLiquidator is ILiquidateCallback, IUniswapV3SwapCallback, IUniswapV3MintCallback {
    IMidnight public immutable midnight;
    IUniswapV3Pool public immutable poolAB;
    IUniswapV3Pool public immutable poolBC;
    address public immutable loanToken;

    constructor(address _midnight, address _poolAB, address _poolBC, address _loanToken) {
        midnight = IMidnight(_midnight);
        poolAB = IUniswapV3Pool(_poolAB);
        poolBC = IUniswapV3Pool(_poolBC);
        loanToken = _loanToken;
        IERC20Minimal(_loanToken).approve(_midnight, type(uint256).max);
    }

    /// @notice Adds full-range liquidity to the given pool (used during test setup).
    function provideLiquidity(IUniswapV3Pool pool, uint128 amount) external {
        pool.mint(address(this), TICK_LOWER, TICK_UPPER, amount, "");
    }

    // ── Morpho liquidation callback
    // ───────────────────────────────────────────

    function onLiquidate(
        bytes32,
        Market memory market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256,
        uint256,
        address,
        address,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == address(midnight));

        // Swap seized collateral (A) → intermediate token (B) on poolAB.
        address collateral = market.collateralParams[collateralIndex].token;
        bool zeroForOneAB = collateral == poolAB.token0();
        (int256 amount0AB, int256 amount1AB) = poolAB.swap(
            address(this),
            zeroForOneAB,
            int256(seizedAssets),
            zeroForOneAB ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1,
            ""
        );

        // Determine how many intermediate tokens were received.
        uint256 intermediateAmount = zeroForOneAB ? uint256(-amount1AB) : uint256(-amount0AB);

        // Swap intermediate (B) → loan token (C) on poolBC.
        address intermediate = zeroForOneAB ? poolAB.token1() : poolAB.token0();
        bool zeroForOneBC = intermediate == poolBC.token0();
        poolBC.swap(
            address(this),
            zeroForOneBC,
            int256(intermediateAmount),
            zeroForOneBC ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1,
            ""
        );

        return CALLBACK_SUCCESS;
    }

    // ── Uniswap V3 callbacks
    // ──────────────────────────────────────────────────

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(poolAB) || msg.sender == address(poolBC));
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        require(msg.sender == address(poolAB) || msg.sender == address(poolBC));
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Owed > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, amount1Owed);
    }
}

/// @notice Multi-collateral single-hop liquidator: maps each collateral to its own Uniswap V3
/// pool (collateral → loan token) and routes seized assets accordingly.
contract UniV3MultiCollateralLiquidator is ILiquidateCallback, IUniswapV3SwapCallback, IUniswapV3MintCallback {
    IMidnight public immutable midnight;
    address public immutable loanToken;
    mapping(address => IUniswapV3Pool) public pools; // collateral → pool
    mapping(address => bool) public isKnownPool;

    constructor(address _midnight, address _loanToken) {
        midnight = IMidnight(_midnight);
        loanToken = _loanToken;
        IERC20Minimal(_loanToken).approve(_midnight, type(uint256).max);
    }

    function registerPool(address collateral, address pool) external {
        pools[collateral] = IUniswapV3Pool(pool);
        isKnownPool[pool] = true;
    }

    function provideLiquidity(IUniswapV3Pool pool, uint128 amount) external {
        pool.mint(address(this), TICK_LOWER, TICK_UPPER, amount, "");
    }

    function onLiquidate(
        bytes32,
        Market memory market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256,
        uint256,
        address,
        address,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == address(midnight));
        address collateral = market.collateralParams[collateralIndex].token;
        IUniswapV3Pool pool = pools[collateral];
        bool zeroForOne = collateral == pool.token0();
        pool.swap(
            address(this),
            zeroForOne,
            int256(seizedAssets),
            zeroForOne ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1,
            ""
        );
        return CALLBACK_SUCCESS;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(isKnownPool[msg.sender]);
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        require(isKnownPool[msg.sender]);
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Owed > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, amount1Owed);
    }
}

/// @notice Multi-collateral two-hop liquidator: routes each seized collateral through a
/// per-collateral AB pool (collateral → intermediate) and a shared BC pool (intermediate → loan).
contract UniV3MultiCollateralTwoHopLiquidator is
    ILiquidateCallback,
    IUniswapV3SwapCallback,
    IUniswapV3MintCallback
{
    IMidnight public immutable midnight;
    IUniswapV3Pool public immutable poolBC;
    address public immutable loanToken;
    mapping(address => IUniswapV3Pool) public poolsAB; // collateral → poolAB
    mapping(address => bool) public isKnownPool; // registered poolAB addresses

    constructor(address _midnight, address _poolBC, address _loanToken) {
        midnight = IMidnight(_midnight);
        poolBC = IUniswapV3Pool(_poolBC);
        loanToken = _loanToken;
        IERC20Minimal(_loanToken).approve(_midnight, type(uint256).max);
    }

    function registerPoolAB(address collateral, address poolAB) external {
        poolsAB[collateral] = IUniswapV3Pool(poolAB);
        isKnownPool[poolAB] = true;
    }

    function provideLiquidityAB(address collateral, uint128 amount) external {
        poolsAB[collateral].mint(address(this), TICK_LOWER, TICK_UPPER, amount, "");
    }

    function provideLiquidityBC(uint128 amount) external {
        poolBC.mint(address(this), TICK_LOWER, TICK_UPPER, amount, "");
    }

    function onLiquidate(
        bytes32,
        Market memory market,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256,
        uint256,
        address,
        address,
        address,
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == address(midnight));

        // Swap seized collateral (A) → intermediate (B) on the per-collateral poolAB.
        address collateral = market.collateralParams[collateralIndex].token;
        IUniswapV3Pool _poolAB = poolsAB[collateral];
        bool zeroForOneAB = collateral == _poolAB.token0();
        (int256 amount0AB, int256 amount1AB) = _poolAB.swap(
            address(this),
            zeroForOneAB,
            int256(seizedAssets),
            zeroForOneAB ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1,
            ""
        );

        // Swap intermediate (B) → loan token (C) on the shared poolBC.
        uint256 intermediateAmount = zeroForOneAB ? uint256(-amount1AB) : uint256(-amount0AB);
        address intermediate = zeroForOneAB ? _poolAB.token1() : _poolAB.token0();
        bool zeroForOneBC = intermediate == poolBC.token0();
        poolBC.swap(
            address(this),
            zeroForOneBC,
            int256(intermediateAmount),
            zeroForOneBC ? UNI_MIN_SQRT_RATIO + 1 : UNI_MAX_SQRT_RATIO - 1,
            ""
        );

        return CALLBACK_SUCCESS;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(isKnownPool[msg.sender] || msg.sender == address(poolBC));
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        require(isKnownPool[msg.sender] || msg.sender == address(poolBC));
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        if (amount0Owed > 0) IERC20Minimal(pool.token0()).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20Minimal(pool.token1()).transfer(msg.sender, amount1Owed);
    }
}

contract UniswapV3GasTest is BaseTest {
    Market internal market;
    IUniswapV3Factory internal uniFactory;
    IUniswapV3Pool internal uniPool;
    UniV3Liquidator internal uniLiquidator;
    IUniswapV3Pool internal uniPoolAB;
    UniV3TwoHopLiquidator internal twoHopLiquidator;

    function setUp() public override {
        super.setUp();
        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 100;
        market.rcfThreshold = 0;

        // Deploy a Uniswap V3 factory and create a 0.3% fee pool for the two tokens.
        // Read bytecode from the pre-built artifact at the project root (not inside out/ which is
        // wiped by forge clean) so v3-core (solc 0.7.6) stays out of the compilation graph.
        bytes memory factoryBytecode = vm.parseJsonBytes(
            vm.readFile("UniswapV3Factory.json"), ".bytecode.object"
        );
        address factory;
        assembly {
            factory := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }
        require(factory != address(0), "UniswapV3Factory deploy failed");
        uniFactory = IUniswapV3Factory(factory);

        // Single-hop pool: loanToken / collateralToken1
        address poolAddr = uniFactory.createPool(address(loanToken), address(collateralToken1), 3000);
        uniPool = IUniswapV3Pool(poolAddr);
        uniPool.initialize(SQRT_PRICE_1_1);

        uniLiquidator = new UniV3Liquidator(address(midnight), address(uniPool));

        // Fund the liquidator with ample reserves and seed the pool with full-range liquidity
        // so the swap during liquidation has negligible price impact.
        deal(uniPool.token0(), address(uniLiquidator), 1e36);
        deal(uniPool.token1(), address(uniLiquidator), 1e36);
        uniLiquidator.provideLiquidity(1_000_000e18);

        // Two-hop pool AB: collateralToken2 / collateralToken1 (collateral → intermediate)
        // Pool BC reuses uniPool: collateralToken1 / loanToken (intermediate → loan)
        address poolABAddr = uniFactory.createPool(address(collateralToken2), address(collateralToken1), 3000);
        uniPoolAB = IUniswapV3Pool(poolABAddr);
        uniPoolAB.initialize(SQRT_PRICE_1_1);

        twoHopLiquidator = new UniV3TwoHopLiquidator(
            address(midnight), address(uniPoolAB), address(uniPool), address(loanToken)
        );
        deal(uniPoolAB.token0(), address(twoHopLiquidator), 1e36);
        deal(uniPoolAB.token1(), address(twoHopLiquidator), 1e36);
        deal(uniPool.token0(), address(twoHopLiquidator), 1e36);
        deal(uniPool.token1(), address(twoHopLiquidator), 1e36);
        twoHopLiquidator.provideLiquidity(uniPoolAB, 1_000_000e18);
        twoHopLiquidator.provideLiquidity(uniPool, 1_000_000e18);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateWithUniswapV3Swap() public {
        uint256 lltv = 0.77e18;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: lltv,
                    maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );

        uint256 units = 1000e18;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        // Drop oracle price to make the position unhealthy (collateral value < debt).
        oracle1.setPrice(0.9e36);
        vm.warp(market.maturity + TIME_TO_MAX_LIF);

        // Seize 100e18 collateral. At oracle price 0.9 and max LIF (~6%), repaidUnits ≈ 84.8e18.
        // The Uniswap swap returns ≈99.7e18 loan tokens (1:1 pool, −0.3% fee), covering repayment.
        uint256 seizeAmount = 100e18;

        uint256 gasBefore = gasleft();
        // Setting callback = uniLiquidator makes it the payer: Morpho pulls loan tokens from it
        // after the swap inside onLiquidate has already filled its balance.
        midnight.liquidate(
            market, 0, seizeAmount, 0, borrower, false, address(uniLiquidator), address(uniLiquidator), ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas Uniswap V3 liquidation swap", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateWithUniswapV3TwoHopSwap() public {
        // Collateral is collateralToken2 (A); swap path: A → collateralToken1 (B) → loanToken (C).
        uint256 lltv = 0.77e18;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: lltv,
                    maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle2)
                })
            );

        uint256 units = 1000e18;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        oracle2.setPrice(0.9e36);
        vm.warp(market.maturity + TIME_TO_MAX_LIF);

        uint256 seizeAmount = 100e18;

        uint256 gasBefore = gasleft();
        midnight.liquidate(
            market, 0, seizeAmount, 0, borrower, false, address(twoHopLiquidator), address(twoHopLiquidator), ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas Uniswap V3 liquidation two-hop swap", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateMaxCollateralsOneHopPerCollat() public {
        uint256 N = MAX_COLLATERALS_PER_BORROWER;
        uint256 lltv = 0.77e18;
        uint256 units = 1000e18;
        // Each token covers 1/N of the total debt capacity at oracle price 1e36.
        // +2 guards against floor-rounding loss in mulDivDown (at most 1 unit lost per token).
        // At oracle price 0.5e36: capacity ≈ 0.5 * units < units → deeply underwater.
        uint256 collateralAmount = (units * 1e18) / lltv / N + 2;
        // Seize half of each collateral slot; keeps seizeAmount < collateralAmount for any N.
        uint256 seizeAmount = collateralAmount / 2;

        // Deploy N collateral tokens and oracles, sort params by token address for the market.
        CollateralParams[] memory params = new CollateralParams[](N);
        for (uint256 i = 0; i < N; i++) {
            params[i] = CollateralParams({
                token: address(new ERC20NoRevert("c")),
                lltv: lltv,
                maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                oracle: address(new Oracle())
            });
        }
        params = sortCollateralParams(params);

        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        _market.rcfThreshold = 0;
        _market.collateralParams = params;

        // Create one Uniswap V3 pool per collateral (collateral_i → loanToken).
        UniV3MultiCollateralLiquidator liquidator =
            new UniV3MultiCollateralLiquidator(address(midnight), address(loanToken));
        deal(address(loanToken), address(liquidator), 1e36);
        for (uint256 i = 0; i < N; i++) {
            address poolAddr = uniFactory.createPool(params[i].token, address(loanToken), 3000);
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddr);
            pool.initialize(SQRT_PRICE_1_1);
            liquidator.registerPool(params[i].token, poolAddr);
            deal(params[i].token, address(liquidator), 1e36);
            liquidator.provideLiquidity(pool, 1_000_000e18);
        }

        // Borrower supplies collateral in each slot.
        for (uint256 i = 0; i < N; i++) {
            deal(params[i].token, borrower, collateralAmount);
            vm.startPrank(borrower);
            IERC20Minimal(params[i].token).approve(address(midnight), collateralAmount);
            midnight.supplyCollateral(_market, i, collateralAmount, borrower);
            vm.stopPrank();
        }
        setupMarket(_market, units);

        // Drop all oracle prices to 0.5 to make the position deeply underwater, then age to max LIF.
        for (uint256 i = 0; i < N; i++) {
            Oracle(params[i].oracle).setPrice(0.5e36);
        }
        vm.warp(_market.maturity + TIME_TO_MAX_LIF);

        // Measure total gas for liquidating all N collateral slots (one swap each).
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < N; i++) {
            midnight.liquidate(
                _market, i, seizeAmount, 0, borrower, false, address(liquidator), address(liquidator), ""
            );
        }
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas Uniswap V3 liquidation max collaterals one hop per collat", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateMaxCollateralsTwoHopsPerCollat() public {
        uint256 N = MAX_COLLATERALS_PER_BORROWER;
        uint256 lltv = 0.77e18;
        uint256 units = 1000e18;
        // +2 guards against floor-rounding loss in mulDivDown (at most 1 unit lost per token).
        uint256 collateralAmount = (units * 1e18) / lltv / N + 2;
        // Seize half of each collateral slot; keeps seizeAmount < collateralAmount for any N.
        uint256 seizeAmount = collateralAmount / 2;

        // Deploy N collateral tokens and oracles, sort params by token address for the market.
        CollateralParams[] memory params = new CollateralParams[](N);
        for (uint256 i = 0; i < N; i++) {
            params[i] = CollateralParams({
                token: address(new ERC20NoRevert("c")),
                lltv: lltv,
                maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                oracle: address(new Oracle())
            });
        }
        params = sortCollateralParams(params);

        Market memory _market;
        _market.loanToken = address(loanToken);
        _market.maturity = block.timestamp + 100;
        _market.rcfThreshold = 0;
        _market.collateralParams = params;

        // Two-hop path per collateral: collateral_i → collateralToken1 (poolAB_i) → loanToken (uniPool = poolBC).
        UniV3MultiCollateralTwoHopLiquidator liquidator =
            new UniV3MultiCollateralTwoHopLiquidator(address(midnight), address(uniPool), address(loanToken));

        // Seed poolBC (uniPool: collateralToken1/loanToken) with extra liquidity.
        deal(uniPool.token0(), address(liquidator), 1e36);
        deal(uniPool.token1(), address(liquidator), 1e36);
        liquidator.provideLiquidityBC(1_000_000e18);

        // Create one poolAB per collateral (collateral_i → collateralToken1) and seed liquidity.
        // Deal collateralToken1 once; 10 pools × ~1M tokens << 1e36.
        deal(address(collateralToken1), address(liquidator), 1e36);
        for (uint256 i = 0; i < N; i++) {
            address poolABAddr = uniFactory.createPool(params[i].token, address(collateralToken1), 3000);
            IUniswapV3Pool poolAB = IUniswapV3Pool(poolABAddr);
            poolAB.initialize(SQRT_PRICE_1_1);
            liquidator.registerPoolAB(params[i].token, poolABAddr);
            deal(params[i].token, address(liquidator), 1e36);
            liquidator.provideLiquidityAB(params[i].token, 1_000_000e18);
        }

        // Borrower supplies collateral in each slot.
        for (uint256 i = 0; i < N; i++) {
            deal(params[i].token, borrower, collateralAmount);
            vm.startPrank(borrower);
            IERC20Minimal(params[i].token).approve(address(midnight), collateralAmount);
            midnight.supplyCollateral(_market, i, collateralAmount, borrower);
            vm.stopPrank();
        }
        setupMarket(_market, units);

        for (uint256 i = 0; i < N; i++) {
            Oracle(params[i].oracle).setPrice(0.5e36);
        }
        vm.warp(_market.maturity + TIME_TO_MAX_LIF);

        // Measure total gas for liquidating all N collateral slots (two swaps each).
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < N; i++) {
            midnight.liquidate(
                _market, i, seizeAmount, 0, borrower, false, address(liquidator), address(liquidator), ""
            );
        }
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas Uniswap V3 liquidation max collaterals two hops per collat", gasUsed);
    }
}
