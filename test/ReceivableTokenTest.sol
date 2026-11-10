// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK, TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";
import {IERC20} from "../src/periphery/receivable-token/interfaces/IERC20.sol";
import {MerkleProofLib} from "../src/periphery/receivable-token/libraries/MerkleProofLib.sol";
import {IReceivableTokenFactory} from "../src/periphery/receivable-token/interfaces/IReceivableTokenFactory.sol";
import {IReceivableToken} from "../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {FlashLiquidator} from "./helpers/FlashLiquidator.sol";
import {MintReceiver} from "./helpers/MintReceiver.sol";
import {TransientReceiver} from "./helpers/TransientReceiver.sol";

contract ReceivableTokenTest is BaseTest {
    using UtilsLib for uint256;

    uint256 internal constant REPORTED = 1_000e18;
    uint256 internal constant OTHER_REPORTED = 500e18;
    uint256 internal constant LENDER_REPORTED = 200e18;
    uint256 internal constant TICK = MAX_TICK - 400; // price < 1, multiple of the default tick spacing.
    bytes32 internal constant ROOT_A = keccak256("A");
    bytes32 internal constant ROOT_B = keccak256("B");
    bytes32 internal constant ROOT_C = keccak256("C");

    address internal payer = makeAddr("payer");
    address internal stranger = makeAddr("stranger");
    address internal minter;
    address internal otherMinter;

    IReceivableTokenFactory internal factory;
    IReceivableToken internal token;
    IReceivableToken internal otherToken;
    bytes32[] internal proof; // minter on token.
    bytes32[] internal otherProof; // otherMinter on otherToken (single leaf, empty proof).
    bytes32[] internal lenderProof; // lender on token.
    bytes32[] internal emptyProof; // proof of a leaf in a single-leaf root.
    uint256 internal maturity;

    function setUp() public override {
        super.setUp();
        minter = borrower;
        otherMinter = otherBorrower;
        midnight.enableLltv(WAD);
        maturity = vm.getBlockTimestamp() + 30 days;

        // Midnight's test tokens do not expose decimals.
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(18)));
        factory = IReceivableTokenFactory(deployCode("ReceivableTokenFactory.sol", abi.encode(address(midnight))));
        token = IReceivableToken(
            factory.createReceivableToken(minter, address(loanToken), "Receivable A", "rA", bytes32(0))
        );
        otherToken = IReceivableToken(
            factory.createReceivableToken(otherMinter, address(loanToken), "Receivable B", "rB", bytes32(0))
        );
        // Roots are per token: the token's has two leaves, the other token's a single one.
        bytes32 leaf = MerkleProofLib.leaf(minter, REPORTED);
        bytes32 lenderLeaf = MerkleProofLib.leaf(lender, LENDER_REPORTED);
        bytes32 otherLeaf = MerkleProofLib.leaf(otherMinter, OTHER_REPORTED);
        bytes32 root = _hashPair(leaf, lenderLeaf);
        proof.push(lenderLeaf);
        lenderProof.push(leaf);
        vm.startPrank(minter);
        token.setRoot(ROOT_A, root);
        token.setRoot(ROOT_B, root);
        token.setRoot(ROOT_C, MerkleProofLib.leaf(liquidator, 0));
        vm.stopPrank();
        vm.prank(otherMinter);
        otherToken.setRoot(ROOT_A, otherLeaf);

        // The lender is whitelisted by proving its leaf, without minting.
        vm.prank(lender);
        token.mint(ROOT_A, 0, LENDER_REPORTED, lenderProof);

        deal(address(loanToken), lender, 10 * REPORTED);
        deal(address(loanToken), payer, 10 * REPORTED);
        vm.prank(minter);
        token.approve(address(midnight), type(uint256).max);
    }

    /// HELPERS ///

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _market() internal view returns (Market memory) {
        return _market(WAD);
    }

    function _market(uint256 lltv) internal view returns (Market memory) {
        return _market(lltv, address(oracle1));
    }

    function _market(uint256 lltv, address oracle) internal view returns (Market memory) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(token), lltv: lltv, liquidationCursor: LIQUIDATION_CURSOR, oracle: oracle
        });
        return Market({
            chainId: block.chainid,
            midnight: address(midnight),
            loanToken: address(loanToken),
            collateralParams: collateralParams,
            maturity: maturity,
            rcfThreshold: 1e18,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }

    function _buyOffer(Market memory market) internal view returns (Offer memory offer) {
        offer.market = market;
        offer.buy = true;
        offer.maker = lender;
        offer.maxUnits = type(uint128).max;
        offer.continuousFeeCap = type(uint256).max;
        offer.ratifier = address(dummyRatifier);
        offer.expiry = type(uint256).max;
        offer.tick = TICK;
    }

    function _mint(uint256 amount) internal {
        vm.prank(minter);
        token.mint(ROOT_A, amount, REPORTED, proof);
    }

    /// @dev The liquidator is whitelisted by proving its `reported` = 0 leaf under ROOT_C, without minting.
    function _whitelistLiquidator() internal {
        vm.prank(liquidator);
        token.mint(ROOT_C, 0, 0, emptyProof);
    }

    /// @dev Receipts are plain transfers to the token.
    function _pay(IReceivableToken _token, uint256 amount) internal {
        vm.prank(payer);
        SafeTransferLib.safeTransfer(address(loanToken), address(_token), amount);
    }

    /// FACTORY ///

    function testCreateReceivableToken() public {
        assertTrue(factory.isReceivableToken(address(token)), "isReceivableToken");
        assertEq(token.name(), "Receivable A", "name");
        assertEq(token.symbol(), "rA", "symbol");
        assertTrue(address(token) != address(otherToken), "distinct");
        assertEq(token.owner(), minter, "owner");
        assertFalse(token.isWhitelisted(minter), "minter whitelisted on first mint");
        assertTrue(token.isWhitelisted(lender), "lender whitelisted by proving its leaf");
        assertFalse(otherToken.isWhitelisted(minter), "whitelist is per token");
        assertEq(token.asset(), address(loanToken), "asset");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.rate(), WAD, "rate");
        assertEq(factory.midnight(), address(midnight), "factory midnight");
        assertEq(token.midnight(), address(midnight), "token midnight");
        assertTrue(otherToken.isWhitelisted(address(midnight)), "midnight whitelisted");

        // Same owner, asset and salt with the same parameters: already deployed. Another salt: another token.
        vm.expectRevert();
        factory.createReceivableToken(minter, address(loanToken), "Receivable A", "rA", bytes32(0));
        address created =
            factory.createReceivableToken(stranger, address(loanToken), "Fresh", "FRS", bytes32(uint256(1)));
        assertTrue(factory.isReceivableToken(created), "fresh registered");
        assertEq(IReceivableToken(created).owner(), stranger, "fresh owner");
    }

    function testDecimalsMirrorAsset() public {
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(6)));
        IReceivableToken created = IReceivableToken(
            factory.createReceivableToken(minter, address(loanToken), "Six", "SIX", bytes32(uint256(6)))
        );
        assertEq(created.decimals(), 6, "decimals");

        vm.clearMockedCalls();
        vm.expectRevert();
        factory.createReceivableToken(minter, address(loanToken), "None", "NONE", bytes32(uint256(7)));
    }

    function testSetters() public {
        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setOwner(address(this));
        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setRoot(ROOT_A, bytes32(0));
        vm.prank(minter);
        token.setOwner(address(this));
        token.setRoot(ROOT_A, bytes32(uint256(1)));
        assertEq(token.owner(), address(this), "owner");
        assertEq(token.roots(ROOT_A), bytes32(uint256(1)), "root");
    }

    /// RATE ///

    function testSetRate() public {
        assertEq(token.rate(), WAD, "rate at creation");

        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.setRate(WAD / 2);

        vm.startPrank(minter);
        vm.expectRevert(IReceivableToken.RateTooHigh.selector);
        token.setRate(WAD + 1);
        vm.expectEmit(address(token));
        emit IReceivableToken.SetRate(WAD / 2);
        token.setRate(WAD / 2);
        vm.stopPrank();
        assertEq(token.rate(), WAD / 2, "rate");
    }

    function testPrice(uint256 newRate) public {
        newRate = bound(newRate, 0, WAD);
        assertEq(token.price(), 1e36, "price at par");
        vm.prank(minter);
        token.setRate(newRate);
        assertEq(token.price(), newRate * 1e18, "price tracks the rate");
    }

    /// MINT ///

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, REPORTED);
        _mint(amount);
        assertEq(token.balanceOf(minter), amount, "balance");
        assertEq(token.totalSupply(), amount, "supply");
        assertEq(token.minted(ROOT_A, minter), amount, "minted");
    }

    function testMintUpToCapacity() public {
        _mint(600e18);
        _mint(400e18);
        vm.expectRevert(IReceivableToken.ExceedsReceivables.selector);
        _mint(1);
    }

    function testMintCapacityIsPerReport() public {
        _mint(REPORTED);
        vm.prank(minter);
        token.mint(ROOT_B, REPORTED, REPORTED, proof);
        assertEq(token.balanceOf(minter), 2 * REPORTED, "balance");
    }

    function testMintOtherMinter() public {
        vm.prank(otherMinter);
        otherToken.mint(ROOT_A, OTHER_REPORTED, OTHER_REPORTED, otherProof);
        assertEq(otherToken.balanceOf(otherMinter), OTHER_REPORTED, "balance");

        // Roots are per token: the minter's proof is not valid on the other token.
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        otherToken.mint(ROOT_A, 1, REPORTED, proof);
    }

    function testMintByAnotherAccountWithAllowance() public {
        vm.prank(lender);
        token.mint(ROOT_A, LENDER_REPORTED, LENDER_REPORTED, lenderProof);
        assertEq(token.balanceOf(lender), LENDER_REPORTED, "lender balance");
        assertEq(token.minted(ROOT_A, lender), LENDER_REPORTED, "lender minted");

        vm.prank(lender);
        vm.expectRevert(IReceivableToken.ExceedsReceivables.selector);
        token.mint(ROOT_A, 1, LENDER_REPORTED, lenderProof);

        // Allowances are per account: the minter's is untouched.
        _mint(REPORTED);
        assertEq(token.totalSupply(), REPORTED + LENDER_REPORTED, "supply");
    }

    function testMintInvalidProof() public {
        vm.startPrank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, 1, REPORTED + 1, proof);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, 1, REPORTED, lenderProof);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(keccak256("unknown"), 1, REPORTED, proof);
        vm.stopPrank();

        // A leaf only works for its own account.
        vm.prank(lender);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, 1, REPORTED, proof);

        // An invalid proof does not whitelist the caller.
        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(ROOT_A, 1, REPORTED, proof);
        assertFalse(token.isWhitelisted(stranger), "stranger not whitelisted");
    }

    /// EXCESS RECEIPTS ///

    function testExcessReceiptsAreExtractedByMintingAndRedeeming() public {
        _mint(300e18);
        _pay(token, 500e18);

        // The minter takes the 200 of excess by minting within its allowance and redeeming.
        _mint(200e18);
        vm.prank(minter);
        token.redeem(200e18, minter);
        assertEq(loanToken.balanceOf(minter), 200e18, "extracted");
        assertEq(token.cash(), 300e18, "cash still backs the outstanding tokens");
        assertEq(token.totalSupply(), 300e18, "supply");

        // Beyond the cash held, minting works but redeeming waits for the receipts.
        _mint(300e18);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        token.redeem(300e18 + 1, minter);
    }

    /// REDEEM ///

    function testRedeemAtFace(uint256 amount) public {
        amount = bound(amount, 1, REPORTED);
        _mint(amount);
        vm.prank(minter);
        token.transfer(lender, amount);
        _pay(token, amount);

        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(lender, address(0), amount);
        vm.expectEmit(address(token));
        emit IReceivableToken.Redeem(lender, lender, amount, amount);
        vm.prank(lender);
        token.redeem(amount, lender);

        assertEq(loanToken.balanceOf(lender), 10 * REPORTED + amount, "lender cash");
        assertEq(token.totalSupply(), 0, "supply");
        assertEq(token.cash(), 0, "cash");
    }

    function testRedeemAtRate(uint256 amount, uint256 newRate) public {
        amount = bound(amount, 1, REPORTED);
        newRate = bound(newRate, 0, WAD);
        _mint(amount);
        _pay(token, amount);
        vm.prank(minter);
        token.setRate(newRate);

        uint256 assets = amount.mulDivDown(newRate, WAD);
        vm.prank(minter);
        assertEq(token.redeem(amount, minter), assets, "assets returned");
        assertEq(loanToken.balanceOf(minter), assets, "assets paid");
        assertEq(token.balanceOf(minter), 0, "tokens burned");
    }

    function testRateCanGoBackUp() public {
        _mint(100e18);
        _pay(token, 100e18);
        vm.startPrank(minter);
        token.setRate(WAD / 2);
        token.setRate(WAD);
        uint256 assets = token.redeem(100e18, minter);
        vm.stopPrank();
        assertEq(assets, 100e18, "redeemed at the new rate");
    }

    function testRateDistributesRecoveryOverReported() public {
        // Reported 1000, minted 600, received 500: the rate is 0.5.
        _mint(600e18);
        _pay(token, 500e18);
        vm.prank(minter);
        token.setRate(WAD / 2);

        vm.prank(minter);
        assertEq(token.redeem(600e18, minter), 300e18, "holders redeem at the rate");

        // The unminted capacity is still extracted by minting and redeeming.
        _mint(400e18);
        vm.prank(minter);
        assertEq(token.redeem(400e18, minter), 200e18, "unminted capacity redeemed");
        assertEq(token.cash(), 0, "cash");
    }

    function testRedeemRequiresCash() public {
        _mint(100e18);
        _pay(token, 60e18);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        token.redeem(60e18 + 1, minter);
        vm.prank(minter);
        token.redeem(60e18, minter);
        assertEq(loanToken.balanceOf(minter), 60e18, "cash");
    }

    function testRedeemInsufficientBalance() public {
        _mint(1);
        _pay(token, 2);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InsufficientBalance.selector);
        token.redeem(2, minter);
    }

    /// WHITELIST ///

    function testMintWhitelists() public {
        assertFalse(token.isWhitelisted(minter), "not whitelisted");
        vm.expectEmit(address(token));
        emit IReceivableToken.Whitelist(minter);
        _mint(0);
        assertTrue(token.isWhitelisted(minter), "whitelisted");

        // A second mint does not emit Whitelist again.
        vm.recordLogs();
        _mint(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IReceivableToken.Whitelist.selector, "no second Whitelist");
        }
    }

    function testWhitelistingIsPermanent() public {
        _mint(1);
        // The owner replaces the root with one that does not contain the lender.
        vm.prank(minter);
        token.setRoot(ROOT_A, MerkleProofLib.leaf(minter, REPORTED));

        assertTrue(token.isWhitelisted(lender), "still whitelisted");
        vm.prank(minter);
        token.transfer(lender, 1);
        assertEq(token.balanceOf(lender), 1, "received");
    }

    function testWhitelistingInHookDoesNotSettle() public {
        _mint(100e18);
        MintReceiver receiver = new MintReceiver();
        vm.prank(minter);
        token.setRoot(ROOT_C, MerkleProofLib.leaf(address(receiver), 0));
        receiver.configure(ROOT_C, 0, emptyProof);

        // Whitelisting itself in the hook does not settle the tokens received before the hook.
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        token.transfer(address(receiver), 100e18);
    }

    function testTransientReceiverSettlesInHook() public {
        _mint(300e18);
        _pay(token, 300e18);
        TransientReceiver receiver = new TransientReceiver();
        receiver.configure(100e18, lender, 200e18);

        vm.prank(minter);
        token.transfer(address(receiver), 300e18);

        // During the hook, the receiver held the tokens transiently.
        assertEq(receiver.observedBalance(), 300e18, "transient balance");
        assertEq(receiver.observedTransientSupply(), 300e18, "transient supply");
        // After the hook, everything is settled.
        assertEq(loanToken.balanceOf(address(receiver)), 100e18, "redeemed");
        assertEq(token.balanceOf(address(receiver)), 0, "transient balance cleared");
        assertEq(token.balanceOf(lender), 200e18, "lender balance");
        assertEq(token.transientSupply(), 0, "transient supply cleared");
        assertEq(token.totalSupply(), 200e18, "total supply");
    }

    function testTransientReceiverMustSettle() public {
        _mint(300e18);
        _pay(token, 300e18);
        TransientReceiver receiver = new TransientReceiver();
        receiver.configure(100e18, lender, 100e18); // leaves 100 behind.

        vm.prank(minter);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        token.transfer(address(receiver), 300e18);
    }

    function testNonWhitelistedAccountWithoutCodeCannotReceive() public {
        _mint(1);
        vm.prank(minter);
        vm.expectRevert();
        token.transfer(stranger, 1);
    }

    function testPermissionlessFlashLiquidation() public {
        // Market with a liquidation incentive, so the liquidator earns something.
        Market memory market = _market(LLTV);
        bytes32 id = toId(market);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        _pay(token, collateral);

        // A non-whitelisted liquidator with no capital liquidates after the incentive has fully ramped up.
        vm.warp(maturity + 1 hours);
        FlashLiquidator flashLiquidator = new FlashLiquidator(address(midnight));
        uint256 seized = units.mulDivDown(maxLif(LLTV, LIQUIDATION_CURSOR), WAD);
        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(address(flashLiquidator), address(0), seized);
        flashLiquidator.liquidate(market, units, minter);
        assertEq(midnight.debt(id, minter), 0, "debt repaid");
        assertEq(midnight.collateral(id, minter, 0), collateral - seized, "collateral seized");
        assertEq(loanToken.balanceOf(address(flashLiquidator)), seized - units, "liquidator profit");
        assertEq(token.balanceOf(address(flashLiquidator)), 0, "liquidator holds no token");
        assertEq(token.transientSupply(), 0, "no transient tokens left");
        assertEq(token.totalSupply(), collateral - seized, "supply");
        assertEq(midnight.withdrawable(id), units, "lender can withdraw");
    }

    function testNonWhitelistedLiquidatorCannotKeepCollateral() public {
        Market memory market = _market(LLTV);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);
        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        _pay(token, collateral);
        vm.warp(maturity + 1 hours);

        // A liquidator contract that does not dispose of the seized tokens in the hook.
        FlashLiquidator flashLiquidator = new FlashLiquidator(address(midnight));
        flashLiquidator.setKeep(true);
        vm.expectRevert(IReceivableToken.TransientBalanceNotSettled.selector);
        flashLiquidator.liquidate(market, units, minter);

        // A plain address, which cannot implement the hook.
        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        vm.expectRevert();
        midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(0), "");

        // The position is untouched, and the same liquidator succeeds once it settles.
        assertEq(midnight.debt(toId(market), minter), units, "debt untouched");
        flashLiquidator.setKeep(false);
        flashLiquidator.liquidate(market, units, minter);
        assertEq(midnight.debt(toId(market), minter), 0, "debt repaid");
        assertEq(token.balanceOf(address(flashLiquidator)), 0, "liquidator holds no token");
    }

    function testMidnightAlwaysWhitelisted() public {
        Market memory market = _market();
        bytes32 id = toId(market);
        uint256 collateral = 100e18;

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        assertEq(token.balanceOf(address(midnight)), collateral, "midnight balance");

        // Midnight is whitelisted without ever proving a leaf.
        assertTrue(token.isWhitelisted(address(midnight)), "midnight whitelisted");

        vm.prank(minter);
        midnight.withdrawCollateral(market, 0, collateral, minter, minter);
        assertEq(midnight.collateral(id, minter, 0), 0, "collateral withdrawn");
        assertEq(token.balanceOf(minter), collateral, "borrower got the tokens back");
    }

    function testMarkdownMakesPositionsLiquidatable() public {
        // A market using the token itself as the collateral oracle.
        Market memory market = _market(LLTV, address(token));
        bytes32 id = toId(market);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        assertTrue(midnight.isHealthy(market, id, minter), "healthy at par");

        // The owner marks the rate down and the position becomes liquidatable before maturity.
        vm.prank(minter);
        token.setRate(WAD / 2);
        assertFalse(midnight.isHealthy(market, id, minter), "unhealthy after markdown");

        // A (0, 0) liquidation realizes the bad debt without seizing collateral.
        uint256 lossFactorBefore = midnight.lossFactor(id);
        vm.prank(liquidator);
        midnight.liquidate(market, 0, 0, 0, minter, false, address(midnight), address(0), "");
        assertLt(midnight.debt(id, minter), units, "bad debt realized");
        assertGt(midnight.lossFactor(id), lossFactorBefore, "loss factor increased");
    }

    /// MIDNIGHT FLOW ///

    function testBorrowOnMidnightAndLiquidateAfterMaturity() public {
        Market memory market = _market();
        bytes32 id = toId(market);
        uint256 units = 600e18;

        // The minter mints receivable tokens, pledges them and sells debt.
        _mint(units);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, units, minter);
        (, uint256 sellerAssets) = take(units, minter, _buyOffer(market));
        assertEq(midnight.debt(id, minter), units, "debt");
        assertEq(sellerAssets, units.mulDivDown(TickLib.tickToPrice(TICK), WAD), "proceeds");
        assertEq(loanToken.balanceOf(minter), sellerAssets, "minter balance");

        // The receipts arrive, backing the collateral.
        _pay(token, units);
        assertEq(token.cash(), units, "cash");

        // After maturity, a whitelisted liquidator repays the debt, seizes the collateral and redeems it at face.
        vm.warp(maturity + 1);
        _whitelistLiquidator();
        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        (uint256 seized, uint256 repaid) =
            midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(0), "");
        assertEq(repaid, units, "repaid");
        assertEq(seized, units, "seized");
        assertEq(midnight.debt(id, minter), 0, "debt repaid");

        vm.prank(liquidator);
        token.redeem(seized, liquidator);
        assertEq(loanToken.balanceOf(liquidator), units, "liquidator cash");
        assertEq(midnight.withdrawable(id), units, "lender can withdraw");
    }
}
