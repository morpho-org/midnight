// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK, TickLib} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";
import {ERC20Lib} from "../src/periphery/libraries/ERC20Lib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";
import {IERC20} from "../src/periphery/receivable-token/interfaces/IERC20.sol";
import {MerkleProofLib} from "../src/periphery/receivable-token/libraries/MerkleProofLib.sol";
import {
    IReceivableTokenFactory,
    Signature,
    CREATE_RECEIVABLE_TOKEN_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/receivable-token/interfaces/IReceivableTokenFactory.sol";
import {IReceivableToken} from "../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";

bytes constant CREATE_RECEIVABLE_TOKEN_TYPE =
    "CreateReceivableToken(address owner,address asset,string name,string symbol,bytes32 root,uint256 nonce)";
bytes constant EIP712_DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)";

contract ReceivableTokenTest is BaseTest {
    using UtilsLib for uint256;

    uint256 internal constant REPORTED = 1_000e18;
    uint256 internal constant OTHER_REPORTED = 500e18;
    uint256 internal constant LENDER_REPORTED = 200e18;
    uint256 internal constant TICK = MAX_TICK - 400; // price < 1, multiple of the default tick spacing.

    address internal payer = makeAddr("payer");
    address internal stranger = makeAddr("stranger");
    address internal signer;
    uint256 internal signerKey;
    address internal otherSigner;
    uint256 internal otherSignerKey;
    address internal minter;
    address internal otherMinter;

    IReceivableTokenFactory internal factory;
    IReceivableToken internal token;
    IReceivableToken internal otherToken;
    bytes32[] internal proof; // minter on token.
    bytes32[] internal otherProof; // otherMinter on otherToken (single leaf, empty proof).
    bytes32[] internal lenderProof; // lender on token.
    uint256 internal maturity;

    function setUp() public override {
        super.setUp();
        (signer, signerKey) = makeAddrAndKey("signer");
        (otherSigner, otherSignerKey) = makeAddrAndKey("otherSigner");
        minter = borrower;
        otherMinter = otherBorrower;
        midnight.enableLltv(WAD);
        maturity = vm.getBlockTimestamp() + 30 days;

        // Midnight's test tokens do not expose decimals.
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(18)));
        factory = IReceivableTokenFactory(deployCode("ReceivableTokenFactory.sol", abi.encode(address(midnight))));
        // Roots are per token: the token's has two leaves, the other token's a single one.
        bytes32 leaf = MerkleProofLib.leaf(minter, REPORTED);
        bytes32 lenderLeaf = MerkleProofLib.leaf(lender, LENDER_REPORTED);
        bytes32 otherLeaf = MerkleProofLib.leaf(otherMinter, OTHER_REPORTED);
        bytes32 root = _hashPair(leaf, lenderLeaf);
        token =
            IReceivableToken(_createToken(signer, signerKey, minter, address(loanToken), "Receivable A", "rA", root));
        otherToken = IReceivableToken(
            _createToken(otherSigner, otherSignerKey, otherMinter, address(loanToken), "Receivable B", "rB", otherLeaf)
        );
        proof.push(lenderLeaf);
        lenderProof.push(leaf);
        vm.prank(minter);
        token.whitelist(lender);

        deal(address(loanToken), lender, 10 * REPORTED);
        deal(address(loanToken), payer, 10 * REPORTED);
        vm.prank(minter);
        token.approve(address(midnight), type(uint256).max);
    }

    /// HELPERS ///

    function _signCreate(
        uint256 key,
        address verifyingFactory,
        uint256 chainId,
        address owner,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 root,
        uint256 nonce
    ) internal pure returns (Signature memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                CREATE_RECEIVABLE_TOKEN_TYPEHASH,
                owner,
                asset,
                keccak256(bytes(name)),
                keccak256(bytes(symbol)),
                root,
                nonce
            )
        );
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, chainId, verifyingFactory));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return Signature({v: v, r: r, s: s});
    }

    function _createToken(
        address _signer,
        uint256 key,
        address owner,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 root
    ) internal returns (address) {
        uint256 nonce = factory.nonces(_signer);
        Signature memory sig =
            _signCreate(key, address(factory), block.chainid, owner, asset, name, symbol, root, nonce);
        return factory.createReceivableToken(_signer, owner, asset, name, symbol, root, nonce, sig);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _market() internal view returns (Market memory) {
        return _market(WAD);
    }

    function _market(uint256 lltv) internal view returns (Market memory) {
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(token), lltv: lltv, liquidationCursor: LIQUIDATION_CURSOR, oracle: address(oracle1)
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
        token.mint(amount, REPORTED, proof);
    }

    function _whitelistLiquidator() internal {
        vm.prank(minter);
        token.whitelist(liquidator);
    }

    /// @dev Receipts are plain transfers to the token.
    function _pay(IReceivableToken _token, uint256 amount) internal {
        vm.prank(payer);
        SafeTransferLib.safeTransfer(address(loanToken), address(_token), amount);
    }

    /// FACTORY ///

    function testCreateReceivableTokenTypeHash() public pure {
        assertEq(CREATE_RECEIVABLE_TOKEN_TYPEHASH, keccak256(CREATE_RECEIVABLE_TOKEN_TYPE), "typehash");
    }

    function testEip712DomainTypeHash() public pure {
        assertEq(EIP712_DOMAIN_TYPEHASH, keccak256(EIP712_DOMAIN_TYPE), "domain typehash");
    }

    function testFactoryConstructorEvent() public {
        vm.expectEmit();
        emit IReceivableTokenFactory.Constructor(address(midnight));
        address created = deployCode("ReceivableTokenFactory.sol", abi.encode(address(midnight)));
        assertEq(IReceivableTokenFactory(created).midnight(), address(midnight), "midnight");
    }

    function testCreateReceivableTokenEvent() public {
        bytes32 root = token.root();
        uint256 nonce = factory.nonces(signer);
        Signature memory sig = _signCreate(
            signerKey, address(factory), block.chainid, minter, address(loanToken), "Fresh", "FRS", root, nonce
        );
        vm.recordLogs();
        vm.prank(stranger);
        address created =
            factory.createReceivableToken(signer, minter, address(loanToken), "Fresh", "FRS", root, nonce, sig);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory creation = logs[logs.length - 1];
        assertEq(creation.emitter, address(factory), "emitter");
        assertEq(creation.topics.length, 4, "topics");
        assertEq(creation.topics[0], IReceivableTokenFactory.CreateReceivableToken.selector, "event");
        assertEq(creation.topics[1], bytes32(uint256(uint160(signer))), "signer");
        assertEq(creation.topics[2], bytes32(uint256(uint160(address(loanToken)))), "asset");
        assertEq(creation.topics[3], bytes32(uint256(uint160(created))), "token");
        assertEq(creation.data, abi.encode(minter, "Fresh", "FRS", root, nonce, stranger), "data");
    }

    function testTransferFromAllowance(uint256 amount) public {
        amount = bound(amount, 0, REPORTED);
        _mint(REPORTED);
        vm.prank(minter);
        token.approve(stranger, REPORTED);
        vm.expectEmit(address(token));
        emit IReceivableToken.Approval(minter, stranger, REPORTED - amount);
        vm.prank(stranger);
        token.transferFrom(minter, lender, amount);
        assertEq(token.allowance(minter, stranger), REPORTED - amount, "allowance");
        assertEq(token.balanceOf(lender), amount, "transferred");

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InsufficientAllowance.selector);
        token.transferFrom(minter, lender, REPORTED - amount + 1);
    }

    function testCreateReceivableToken() public {
        assertTrue(factory.isReceivableToken(address(token)), "isReceivableToken");
        assertEq(token.name(), "Receivable A", "name");
        assertEq(token.symbol(), "rA", "symbol");
        assertTrue(address(token) != address(otherToken), "distinct");
        assertEq(token.owner(), minter, "owner");
        assertEq(token.signer(), signer, "signer");
        assertEq(otherToken.signer(), otherSigner, "other signer");
        assertEq(factory.nonces(signer), 1, "signer nonce");
        assertEq(factory.nonces(otherSigner), 1, "otherSigner nonce");
        assertFalse(token.isWhitelisted(minter), "minter whitelisted on first mint");
        assertTrue(token.isWhitelisted(lender), "lender whitelisted by owner");
        assertFalse(otherToken.isWhitelisted(minter), "whitelist is per token");
        assertEq(token.asset(), address(loanToken), "asset");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(factory.midnight(), address(midnight), "factory midnight");
        assertEq(token.midnight(), address(midnight), "token midnight");
        assertTrue(otherToken.isWhitelisted(address(midnight)), "midnight whitelisted");
        bytes32 root = _hashPair(MerkleProofLib.leaf(minter, REPORTED), MerkleProofLib.leaf(lender, LENDER_REPORTED));
        bytes32 otherRoot = MerkleProofLib.leaf(otherMinter, OTHER_REPORTED);
        assertEq(token.root(), root, "root");
        assertEq(otherToken.root(), otherRoot, "other root");

        // Replaying nonce 0 reverts with InvalidNonce.
        Signature memory replaySig = _signCreate(
            signerKey, address(factory), block.chainid, minter, address(loanToken), "Receivable A", "rA", root, 0
        );
        vm.expectRevert(IReceivableTokenFactory.InvalidNonce.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Receivable A", "rA", root, 0, replaySig);

        // Next sequential nonce succeeds, even when submitted by a stranger.
        Signature memory nextSig = _signCreate(
            signerKey, address(factory), block.chainid, stranger, address(loanToken), "Fresh", "FRS", root, 1
        );
        vm.prank(stranger);
        address created =
            factory.createReceivableToken(signer, stranger, address(loanToken), "Fresh", "FRS", root, 1, nextSig);
        assertTrue(factory.isReceivableToken(created), "fresh registered");
        assertEq(IReceivableToken(created).owner(), stranger, "fresh owner");
        assertEq(IReceivableToken(created).signer(), signer, "fresh signer");
        assertEq(factory.nonces(signer), 2, "signer nonce incremented");
    }

    function testCreateReceivableTokenInvalidNonce() public {
        bytes32 root = token.root();
        Signature memory sig = _signCreate(
            signerKey, address(factory), block.chainid, minter, address(loanToken), "Wrong Nonce", "WN", root, 2
        );
        vm.expectRevert(IReceivableTokenFactory.InvalidNonce.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Wrong Nonce", "WN", root, 2, sig);
        assertEq(factory.nonces(signer), 1, "nonce unchanged");
    }

    function testCreateReceivableTokenInvalidSignature() public {
        bytes32 root = token.root();
        uint256 nonce = factory.nonces(signer);
        Signature memory validSig = _signCreate(
            signerKey, address(factory), block.chainid, minter, address(loanToken), "Signed", "SIG", root, nonce
        );

        // Wrong signer key.
        Signature memory wrongKeySig = _signCreate(
            otherSignerKey, address(factory), block.chainid, minter, address(loanToken), "Signed", "SIG", root, nonce
        );
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "SIG", root, nonce, wrongKeySig);

        // ecrecover returns address(0) when v is invalid.
        Signature memory zeroSig = Signature({v: 0, r: validSig.r, s: validSig.s});
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "SIG", root, nonce, zeroSig);

        // Tampered parameters all fail signature verification.
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, stranger, address(loanToken), "Signed", "SIG", root, nonce, validSig);

        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(otherToken), "Signed", "SIG", root, nonce, validSig);

        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Tampered", "SIG", root, nonce, validSig);

        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "TMP", root, nonce, validSig);

        bytes32 otherRoot = otherToken.root();
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "SIG", otherRoot, nonce, validSig);

        // Wrong chainId in domain separator.
        Signature memory wrongChainSig = _signCreate(
            signerKey, address(factory), block.chainid + 1, minter, address(loanToken), "Signed", "SIG", root, nonce
        );
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "SIG", root, nonce, wrongChainSig);

        // Wrong factory (verifyingContract) in domain separator.
        Signature memory wrongFactorySig =
            _signCreate(signerKey, stranger, block.chainid, minter, address(loanToken), "Signed", "SIG", root, nonce);
        vm.expectRevert(IReceivableTokenFactory.InvalidSignature.selector);
        factory.createReceivableToken(signer, minter, address(loanToken), "Signed", "SIG", root, nonce, wrongFactorySig);

        assertEq(factory.nonces(signer), nonce, "nonce unchanged");
    }

    function testDecimalsMirrorAsset() public {
        bytes32 root = token.root();
        vm.mockCall(address(loanToken), abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(6)));
        vm.expectEmit();
        emit IReceivableToken.Constructor(address(midnight), address(loanToken), minter, signer, "Six", "SIX", 6, root);
        IReceivableToken created =
            IReceivableToken(_createToken(signer, signerKey, minter, address(loanToken), "Six", "SIX", root));
        assertEq(created.decimals(), 6, "decimals");

        vm.clearMockedCalls();
        uint256 nonce = factory.nonces(signer);
        Signature memory sig = _signCreate(
            signerKey, address(factory), block.chainid, minter, address(loanToken), "None", "NONE", root, nonce
        );
        vm.expectRevert();
        factory.createReceivableToken(signer, minter, address(loanToken), "None", "NONE", root, nonce, sig);
    }

    /// MINT ///

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, REPORTED);
        vm.expectEmit(address(token));
        emit IReceivableToken.Mint(minter, amount, REPORTED);
        _mint(amount);
        assertEq(token.balanceOf(minter), amount, "balance");
        assertEq(token.totalSupply(), amount, "supply");
        assertEq(token.minted(minter), amount, "minted");
    }

    function testMintUpToCapacity() public {
        _mint(600e18);
        _mint(400e18);
        vm.expectRevert(IReceivableToken.ExceedsReceivables.selector);
        _mint(1);
    }

    function testRedeemingDoesNotRestoreMintingCapacity() public {
        _mint(REPORTED);
        _pay(token, REPORTED + 1);
        vm.prank(minter);
        token.redeem(REPORTED, minter);
        assertEq(token.cash(), 1, "excess receipts");
        vm.expectRevert(IReceivableToken.ExceedsReceivables.selector);
        _mint(1);
    }

    function testMintOtherMinter() public {
        vm.prank(otherMinter);
        otherToken.mint(OTHER_REPORTED, OTHER_REPORTED, otherProof);
        assertEq(otherToken.balanceOf(otherMinter), OTHER_REPORTED, "balance");

        // Roots are per token: the minter's proof is not valid on the other token.
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        otherToken.mint(1, REPORTED, proof);
    }

    function testMintByAnotherAccountWithAllowance() public {
        vm.prank(lender);
        token.mint(LENDER_REPORTED, LENDER_REPORTED, lenderProof);
        assertEq(token.balanceOf(lender), LENDER_REPORTED, "lender balance");
        assertEq(token.minted(lender), LENDER_REPORTED, "lender minted");

        vm.prank(lender);
        vm.expectRevert(IReceivableToken.ExceedsReceivables.selector);
        token.mint(1, LENDER_REPORTED, lenderProof);

        // Allowances are per account: the minter's is untouched.
        _mint(REPORTED);
        assertEq(token.totalSupply(), REPORTED + LENDER_REPORTED, "supply");
    }

    function testMintInvalidProof() public {
        vm.startPrank(minter);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(1, REPORTED + 1, proof);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(1, REPORTED, lenderProof);
        vm.stopPrank();

        // A leaf only works for its own account.
        vm.prank(lender);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(1, REPORTED, proof);

        // An invalid proof does not whitelist the caller.
        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidProof.selector);
        token.mint(1, REPORTED, proof);
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
        emit IReceivableToken.Redeem(lender, lender, amount);
        vm.prank(lender);
        token.redeem(amount, lender);

        assertEq(loanToken.balanceOf(lender), 10 * REPORTED + amount, "lender cash");
        assertEq(token.totalSupply(), 0, "supply");
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

    function testWhitelistWithoutMinting() public {
        assertFalse(token.isWhitelisted(stranger), "not whitelisted");
        vm.expectEmit(address(token));
        emit IReceivableToken.Whitelist(stranger);
        vm.prank(minter);
        token.whitelist(stranger);
        assertTrue(token.isWhitelisted(stranger), "whitelisted");
        assertEq(token.balanceOf(stranger), 0, "balance");
        assertEq(token.totalSupply(), 0, "supply");
        assertEq(token.minted(stranger), 0, "minted");
    }

    function testWhitelistOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.NotOwner.selector);
        token.whitelist(stranger);
        assertFalse(token.isWhitelisted(stranger), "stranger not whitelisted");
    }

    function testMintWhitelists() public {
        assertFalse(token.isWhitelisted(minter), "not whitelisted");
        vm.expectEmit(address(token));
        emit IReceivableToken.Whitelist(minter);
        _mint(1);
        assertTrue(token.isWhitelisted(minter), "whitelisted");

        // A second mint does not emit Whitelist again.
        vm.recordLogs();
        _mint(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IReceivableToken.Whitelist.selector, "no second Whitelist");
        }
    }

    function testWhitelistIsIdempotent() public {
        _mint(1);
        vm.recordLogs();
        vm.prank(minter);
        token.whitelist(lender);
        assertEq(vm.getRecordedLogs().length, 0, "no second Whitelist");

        assertTrue(token.isWhitelisted(lender), "still whitelisted");
        vm.prank(minter);
        token.transfer(lender, 1);
        assertEq(token.balanceOf(lender), 1, "received");
    }

    function testNonWhitelistedCannotReceive() public {
        _mint(1);
        vm.prank(minter);
        vm.expectRevert(IReceivableToken.NotWhitelisted.selector);
        token.transfer(stranger, 1);

        // Zero-value transfers succeed for any account.
        vm.prank(minter);
        token.transfer(stranger, 0);
    }

    function testTokenIsWhitelisted() public view {
        assertTrue(token.isWhitelisted(address(token)), "token whitelisted");
    }

    /// LIQUIDATIONS ///

    /// @dev Supplies collateral, sells debt on a market with a liquidation incentive and pays the receipts.
    function _borrowAndPay(Market memory market) internal returns (uint256 units, uint256 collateral) {
        units = 600e18;
        collateral = units.mulDivUp(WAD, LLTV);
        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        _pay(token, collateral);
    }

    function _liquidateThroughToken(Market memory market, uint256 repaidUnits) internal returns (uint256, uint256) {
        vm.prank(stranger);
        return midnight.liquidate(market, 0, 0, repaidUnits, minter, true, address(token), address(token), "");
    }

    function testPermissionlessLiquidationThroughToken() public {
        Market memory market = _market(LLTV);
        bytes32 id = toId(market);
        (uint256 units, uint256 collateral) = _borrowAndPay(market);

        // A non-whitelisted liquidator with no capital liquidates after the incentive has fully ramped up.
        vm.warp(maturity + 1 hours);
        assertFalse(token.isWhitelisted(stranger), "liquidator not whitelisted");
        uint256 seized = units.mulDivDown(maxLif(LLTV, LIQUIDATION_CURSOR), WAD);
        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(address(token), address(0), seized);
        vm.expectEmit(address(token));
        emit IReceivableToken.RedeemSeized(stranger, id, minter, seized, units);
        (uint256 seizedAssets, uint256 repaid) = _liquidateThroughToken(market, units);

        assertEq(seizedAssets, seized, "seized");
        assertEq(repaid, units, "repaid");
        assertEq(midnight.debt(id, minter), 0, "debt repaid");
        assertEq(midnight.collateral(id, minter, 0), collateral - seized, "collateral seized");
        assertEq(loanToken.balanceOf(stranger), seized - units, "liquidator profit");
        assertEq(token.balanceOf(address(token)), 0, "seized tokens burned");
        assertEq(token.balanceOf(stranger), 0, "liquidator holds no token");
        assertEq(token.totalSupply(), collateral - seized, "supply");
        assertEq(token.cash(), collateral - seized, "cash backs the remaining supply");
        assertEq(loanToken.allowance(address(token), address(midnight)), 0, "allowance spent");
        assertEq(midnight.withdrawable(id), units, "lender can withdraw");
    }

    function testNonWhitelistedLiquidatorCannotKeepCollateral() public {
        Market memory market = _market(LLTV);
        (uint256 units,) = _borrowAndPay(market);
        vm.warp(maturity + 1 hours);

        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        vm.expectRevert(IReceivableToken.NotWhitelisted.selector);
        midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(0), "");
    }

    function testOnLiquidateOnlyMidnight() public {
        Market memory market = _market(LLTV);
        vm.expectRevert(IReceivableToken.NotMidnight.selector);
        token.onLiquidate(stranger, toId(market), market, 0, 0, 0, minter, address(token), "", 0);
    }

    function testOnLiquidateRequiresTokenAsReceiver() public {
        Market memory market = _market(LLTV);
        (uint256 units,) = _borrowAndPay(market);
        vm.warp(maturity + 1 hours);
        _whitelistLiquidator();

        vm.prank(stranger);
        vm.expectRevert(IReceivableToken.InvalidLiquidation.selector);
        midnight.liquidate(market, 0, 0, units, minter, true, liquidator, address(token), "");
    }

    function testOnLiquidateRequiresTokenAsCollateral() public {
        // The token holds stray tokens of its own, which a liquidation of another collateral must not burn.
        _mint(1e18);
        vm.prank(minter);
        token.transfer(address(token), 1e18);

        Market memory market = _market(LLTV);
        market.collateralParams[0].token = address(otherToken);
        vm.prank(address(midnight));
        vm.expectRevert(IReceivableToken.InvalidLiquidation.selector);
        token.onLiquidate(stranger, toId(market), market, 0, 1e18, 0, minter, address(token), "", 0);
    }

    function testOnLiquidateRequiresAssetAsLoanToken() public {
        Market memory market = _market(LLTV);
        market.loanToken = address(otherToken);
        vm.prank(address(midnight));
        vm.expectRevert(IReceivableToken.InvalidLiquidation.selector);
        token.onLiquidate(stranger, toId(market), market, 0, 0, 0, minter, address(token), "", 0);
    }

    function testOnLiquidateNeedsNoCapital(uint256 seizedAssets, uint256 elapsed) public {
        // Even when the incentive is close to 1, right after maturity, the seized tokens cover the repaid units.
        Market memory market = _market(LLTV);
        (uint256 units,) = _borrowAndPay(market);
        seizedAssets = bound(seizedAssets, 1, units);
        elapsed = bound(elapsed, 1, 1 hours);
        vm.warp(maturity + elapsed);

        vm.prank(stranger);
        (uint256 seized, uint256 repaid) =
            midnight.liquidate(market, 0, seizedAssets, 0, minter, true, address(token), address(token), "");
        assertLe(repaid, seized, "repaid at most seized");
        assertEq(loanToken.balanceOf(stranger), seized - repaid, "liquidator profit");
    }

    function testOnLiquidateRevertsWhenOracleAbovePar() public {
        Market memory market = _market(LLTV);
        (uint256 units,) = _borrowAndPay(market);
        vm.warp(maturity + 1);
        oracle1.setPrice(2e36);

        // Above the incentive, the repaid units exceed the seized tokens, so paying the liquidator underflows.
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        _liquidateThroughToken(market, units);
    }

    function testOnLiquidateInsufficientCash() public {
        Market memory market = _market(LLTV);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);
        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        vm.warp(maturity + 1 hours);

        // The receipts have not arrived.
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        _liquidateThroughToken(market, units);
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

    function testZeroValueLiquidationToAnyReceiver() public {
        Market memory market = _market(LLTV);
        bytes32 id = toId(market);
        uint256 units = 600e18;
        uint256 collateral = units.mulDivUp(WAD, LLTV);

        _mint(collateral);
        vm.prank(minter);
        midnight.supplyCollateral(market, 0, collateral, minter);
        take(units, minter, _buyOffer(market));
        assertTrue(midnight.isHealthy(market, id, minter), "healthy at par");

        // The market's oracle marks the token down and the position becomes liquidatable before maturity.
        oracle1.setPrice(0.5e36);
        assertFalse(midnight.isHealthy(market, id, minter), "unhealthy after markdown");

        // A (0, 0) liquidation realizes the bad debt without seizing collateral.
        uint256 lossFactorBefore = midnight.lossFactor(id);
        assertFalse(token.isWhitelisted(stranger), "receiver not whitelisted");
        assertEq(stranger.code.length, 0, "receiver is EOA");
        vm.expectEmit(address(token));
        emit IReceivableToken.Transfer(address(midnight), stranger, 0);
        vm.prank(liquidator);
        midnight.liquidate(market, 0, 0, 0, minter, false, stranger, address(0), "");
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
